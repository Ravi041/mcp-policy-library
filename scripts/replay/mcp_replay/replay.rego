# METADATA
# title: Trace replay
# description: >-
#   Re-evaluates recorded tool calls against the loaded policies and config, and classes each
#   one by how its outcome moved. This is test tooling. It is not part of the policy bundle.
package mcp_replay

import data.mcp.main
import data.mcp_adapters.agentgateway as adapter

library_path := "mcp/main/decision"

adapter_path := "mcp_adapters/agentgateway/response"

# How open each outcome is. A higher rank after replay is a loosening, a lower one a tightening.
outcome_rank := {"deny": 0, "approve": 1, "allow": 2}

default accepted_ids := set()

accepted_ids := {id | some id in input.accepted}

# --- Reading one decision-log record -----------------------------------------------------------

# The library input of each record, by its position in the trace. A record logged at the
# library entrypoint already holds it.
library_inputs[index] := record.input if {
	some index, record in input.records
	record.path == library_path
}

# A record logged at the adapter holds the gateway's check. The adapter turns it into the
# library input, so a replay also covers the adapter. Calls it never sent to the library, such
# as initialize or a truncated body, yield nothing and are skipped.
library_inputs[index] := normalized if {
	some index, record in input.records
	record.path == adapter_path

	# regal ignore:with-outside-test-context
	adapter.is_checked_tool_call with input as record.input

	# regal ignore:with-outside-test-context
	normalized := adapter.library_input with input as record.input
}

recorded_decision(record) := record.result if record.path == library_path

recorded_decision(record) := {"allow": true, "require_approval": false, "deny": []} if {
	record.path == adapter_path
	record.result.allowed == true
}

recorded_decision(record) := json.unmarshal(record.result.body).error.data.decision if {
	record.path == adapter_path
	record.result.allowed == false
}

outcome(decision) := "allow" if {
	decision.allow == true
	decision.require_approval == false
}

outcome(decision) := "approve" if {
	decision.allow == false
	decision.require_approval == true
}

outcome(decision) := "deny" if {
	decision.allow == false
	decision.require_approval == false
}

codes(decision) := sort({reason.code | some reason in decision.deny})

schema_errors(document, schema) := sort({problem.error | some problem in json.match_schema(document, schema)[1]})

# --- Classing the move -------------------------------------------------------------------------

change(before, after) := "loosened" if outcome_rank[outcome(after)] > outcome_rank[outcome(before)]

change(before, after) := "tightened" if outcome_rank[outcome(after)] < outcome_rank[outcome(before)]

change(before, after) := "reasons_changed" if {
	outcome(after) == outcome(before)
	codes(after) != codes(before)
}

change(before, after) := "unchanged" if {
	outcome(after) == outcome(before)
	codes(after) == codes(before)
}

describe(decision) := outcome(decision) if count(decision.deny) == 0

describe(decision) := sprintf("deny[%s]", [concat(",", codes(decision))]) if count(decision.deny) > 0

# A helper rule, because `not is_string(x)` is undefined rather than true when x is missing.
has_id(record) if is_string(record.decision_id)

record_id(record, _) := record.decision_id if has_id(record)

record_id(record, index) := sprintf("record-%d", [index + 1]) if not has_id(record)

# --- Results -----------------------------------------------------------------------------------

# One entry per record that holds a tool call with a readable recorded decision. Tool arguments
# are left out on purpose: traces hold SQL and file contents, and reports end up in CI logs.
results contains result if {
	some index, record in input.records
	normalized := library_inputs[index]
	before := recorded_decision(record)
	before_outcome := outcome(before)

	# regal ignore:with-outside-test-context
	after := main.decision with input as normalized
	result := {
		"index": index,
		"id": record_id(record, index),
		"server": object.get(normalized, ["server", "name"], "<missing>"),
		"tool": object.get(normalized, ["tool", "name"], "<missing>"),
		"before": describe(before),
		"after": describe(after),
		"before_outcome": before_outcome,
		"change": change(before, after),
		"input_errors": schema_errors(normalized, input.input_schema),
		"decision_errors": schema_errors(after, input.decision_schema),
	}
}

moved(result) if result.change in {"loosened", "tightened"}

is_accepted(result) if result.id in accepted_ids

# A refusal says nothing about whether the gateway built a valid input: garbage is refused
# too. An input that was allowed or held for approval must be valid against the contract.
has_contract_problem(result) if {
	result.before_outcome != "deny"
	count(result.input_errors) > 0
}

has_contract_problem(result) if count(result.decision_errors) > 0

failures contains result if {
	some result in results
	moved(result)
	not is_accepted(result)
}

failures contains result if {
	some result in results
	has_contract_problem(result)
}

count_of(kind) := count({result.index | some result in results; result.change == kind})

# --- Report ------------------------------------------------------------------------------------

labels := {
	"loosened": "LOOSENED ",
	"tightened": "TIGHTENED",
	"reasons_changed": "REASONS  ",
}

verdict(result) := "accepted" if {
	moved(result)
	is_accepted(result)
}

verdict(result) := "FAIL" if {
	moved(result)
	not is_accepted(result)
}

verdict(result) := "note" if result.change == "reasons_changed"

change_lines := [line |
	some result in sort_by_index(results)
	result.change != "unchanged"
	line := sprintf("%s %-8s %s  %s/%s  %s -> %s", [
		labels[result.change],
		verdict(result),
		result.id,
		result.server,
		result.tool,
		result.before,
		result.after,
	])
]

contract_lines := [line |
	some result in sort_by_index(results)
	has_contract_problem(result)
	line := sprintf("CONTRACT  FAIL     %s  %s/%s  %s", [
		result.id,
		result.server,
		result.tool,
		concat("; ", array.concat(result.input_errors, result.decision_errors)),
	])
]

sort_by_index(items) := [item |
	some index in sort({item.index | some item in items})
	some item in items
	item.index == index
]

summary := sprintf(
	"replayed %d tool calls (%d records skipped): %d unchanged, %d reasons changed, %d loosened, %d tightened, %d failed",
	[
		count(results),
		count(input.records) - count(results),
		count_of("unchanged"),
		count_of("reasons_changed"),
		count_of("loosened"),
		count_of("tightened"),
		count(failures),
	],
)

# METADATA
# description: The replay report. ok is false when any record failed or nothing could be replayed.
# entrypoint: true
report := {
	"ok": ok,
	"lines": array.flatten([change_lines, contract_lines, [summary]]),
}

default ok := false

ok if {
	count(failures) == 0
	count(results) > 0
}
