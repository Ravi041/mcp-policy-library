package mcp_replay_test

import data.mcp_replay

call := {
	"version": "1.0",
	"principal": {"id": "alice", "type": "user"},
	"server": {"name": "github"},
	"tool": {"name": "any_tool"},
	"arguments": {},
}

allowing_pack := {"allow": true, "deny": set(), "require_approval": false}

approving_pack := {"allow": true, "deny": set(), "require_approval": true}

denying_pack := {
	"allow": true,
	"deny": {{"code": "github.nope", "message": "no", "pack": "github"}},
	"require_approval": false,
}

was_allowed := {"allow": true, "require_approval": false, "deny": []}

was_held := {"allow": false, "require_approval": true, "deny": []}

was_denied := {"allow": false, "require_approval": false, "deny": [{"code": "github.nope", "message": "no", "pack": "github"}]}

was_denied_otherwise := {"allow": false, "require_approval": false, "deny": [{"code": "github.old", "message": "no", "pack": "github"}]}

record(id, before) := {"decision_id": id, "path": "mcp/main/decision", "input": call, "result": before}

# Accepts every document, so a test is about outcomes unless it says otherwise.
any_schema := {}

trace_of(records) := {"records": records, "input_schema": any_schema, "decision_schema": any_schema}

report_for(records, pack) := report if {
	report := mcp_replay.report with input as trace_of(records) with data.mcp.packs.github as pack
}

changes(records, pack) := {result.id: result.change |
	some result in mcp_replay.results with input as trace_of(records) with data.mcp.packs.github as pack
}

test_same_outcome_passes if {
	report := report_for([record("a", was_allowed)], allowing_pack)
	report.ok == true
	count(report.lines) == 1
	contains(report.lines[0], "replayed 1 tool calls (0 records skipped): 1 unchanged")
}

test_every_move_is_classed if {
	changes([record("a", was_denied)], allowing_pack) == {"a": "loosened"}
	changes([record("a", was_denied)], approving_pack) == {"a": "loosened"}
	changes([record("a", was_held)], allowing_pack) == {"a": "loosened"}
	changes([record("a", was_allowed)], denying_pack) == {"a": "tightened"}
	changes([record("a", was_allowed)], approving_pack) == {"a": "tightened"}
	changes([record("a", was_held)], denying_pack) == {"a": "tightened"}
	changes([record("a", was_held)], approving_pack) == {"a": "unchanged"}
	changes([record("a", was_denied)], denying_pack) == {"a": "unchanged"}
	changes([record("a", was_denied_otherwise)], denying_pack) == {"a": "reasons_changed"}
}

test_loosening_fails if {
	report := report_for([record("a", was_denied)], allowing_pack)
	report.ok == false
	startswith(report.lines[0], "LOOSENED  FAIL     a  github/any_tool  deny[github.nope] -> allow")
}

test_tightening_fails if {
	report := report_for([record("a", was_allowed)], denying_pack)
	report.ok == false
	startswith(report.lines[0], "TIGHTENED FAIL     a  github/any_tool  allow -> deny[github.nope]")
}

test_one_moved_call_fails_a_trace_of_good_ones if {
	pack := object.union(allowing_pack, {"allow": false})
	records := [record("a", was_denied_otherwise), record("b", was_allowed)]
	report := mcp_replay.report with input as trace_of(records) with data.mcp.packs.github as pack
	report.ok == false
}

test_changed_reason_is_reported_and_passes if {
	report := report_for([record("a", was_denied_otherwise)], denying_pack)
	report.ok == true
	startswith(report.lines[0], "REASONS   note     a  github/any_tool  deny[github.old] -> deny[github.nope]")
}

test_accepted_move_passes_and_is_still_reported if {
	accepted := object.union(trace_of([record("a", was_allowed), record("b", was_allowed)]), {"accepted": ["a", "b"]})
	report := mcp_replay.report with input as accepted with data.mcp.packs.github as denying_pack
	report.ok == true
	startswith(report.lines[0], "TIGHTENED accepted a")
}

test_accepting_one_call_does_not_accept_another if {
	accepted := object.union(trace_of([record("a", was_allowed), record("b", was_allowed)]), {"accepted": ["a"]})
	report := mcp_replay.report with input as accepted with data.mcp.packs.github as denying_pack
	report.ok == false
}

test_report_never_shows_arguments if {
	secret := object.union(call, {"arguments": {"sql": "SELECT secret_value"}})
	records := [{"decision_id": "a", "path": "mcp/main/decision", "input": secret, "result": was_allowed}]
	report := report_for(records, denying_pack)
	every line in report.lines {
		not contains(line, "secret_value")
	}
}

test_record_without_an_id_is_named_by_position if {
	records := [object.remove(record("a", was_allowed), ["decision_id"])]
	changes(records, denying_pack) == {"record-1": "tightened"}
}

# Records that are not tool calls, or whose recorded decision cannot be read, are skipped.

test_unreadable_records_are_skipped if {
	records := [
		record("a", was_allowed),
		{"decision_id": "b", "path": "some/other/query", "input": call, "result": was_allowed},
		{"decision_id": "c", "path": "mcp/main/decision", "input": call},
		{"decision_id": "d", "path": "mcp/main/decision", "input": call, "result": {"allow": "yes"}},
	]
	report := report_for(records, allowing_pack)
	report.ok == true
	contains(report.lines[0], "replayed 1 tool calls (3 records skipped)")
}

test_trace_with_nothing_to_replay_fails if {
	report := report_for([{"decision_id": "b", "path": "some/other/query", "input": {}, "result": {}}], allowing_pack)
	report.ok == false
}

# The contract. An input that was let through must be valid; a refused one may be anything.

strict_schema := {"type": "object", "required": ["request_id"]}

with_schema(records) := object.union(trace_of(records), {"input_schema": strict_schema})

test_allowed_input_that_breaks_the_schema_fails if {
	report := mcp_replay.report with input as with_schema([record("a", was_allowed)])
		with data.mcp.packs.github as allowing_pack
	report.ok == false
	startswith(report.lines[0], "CONTRACT  FAIL     a  github/any_tool  ")
	contains(report.lines[0], "request_id")
}

test_refused_input_that_breaks_the_schema_passes if {
	report := mcp_replay.report with input as with_schema([record("a", was_denied)])
		with data.mcp.packs.github as denying_pack
	report.ok == true
}

test_decision_that_breaks_the_schema_fails if {
	broken := object.union(trace_of([record("a", was_denied)]), {"decision_schema": {"required": ["nope"]}})
	report := mcp_replay.report with input as broken with data.mcp.packs.github as denying_pack
	report.ok == false
}

# Records logged at the agentgateway adapter hold the gateway's check, not the library input.

check(body) := {
	"attributes": {
		"contextExtensions": {"mcp_server": "github"},
		"metadataContext": {"filterMetadata": {"envoy.filters.http.jwt_authn": {"jwt_payload": {"sub": "alice"}}}},
		"request": {"http": {"id": "req-1", "method": "POST", "headers": {}}, "time": {"seconds": 1793944770, "nanos": 0}},
	},
	"parsed_body": body,
	"truncated_body": false,
}

tool_call := check({"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "any_tool", "arguments": {}}})

refusal(decision) := {"allowed": false, "body": json.marshal({"error": {"code": -32001, "data": {"decision": decision}}})}

adapter_record(id, request, result) := {
	"decision_id": id,
	"path": "mcp_adapters/agentgateway/response",
	"input": request,
	"result": result,
}

test_adapter_records_are_normalized_and_replayed if {
	records := [
		adapter_record("a", tool_call, {"allowed": true}),
		adapter_record("b", tool_call, refusal(was_denied)),
		adapter_record("c", tool_call, refusal(was_held)),
	]
	changes(records, allowing_pack) == {"a": "unchanged", "b": "loosened", "c": "loosened"}
	changes(records, denying_pack) == {"a": "tightened", "b": "unchanged", "c": "tightened"}
}

test_adapter_records_that_are_not_tool_calls_are_skipped if {
	records := [
		adapter_record("a", check({"jsonrpc": "2.0", "id": 1, "method": "initialize"}), {"allowed": true}),
		adapter_record("b", object.union(tool_call, {"truncated_body": true}), {"allowed": false, "body": "{}"}),
		adapter_record("c", tool_call, {"allowed": false, "body": "not json"}),
	]
	changes(records, allowing_pack) == {}
}
