package mcp.main_test

import data.mcp.main

base_input := {
	"version": "1.0",
	"principal": {"id": "alice", "type": "user"},
	"server": {"name": "github"},
	"tool": {"name": "any_tool"},
	"arguments": {},
}

allowing_pack := {"allow": true, "deny": set(), "require_approval": false, "audit_tags": {"pack:tag"}}

denying_pack := {
	"allow": true,
	"deny": {{"code": "github.nope", "message": "no", "pack": "github"}},
	"require_approval": false,
}

approving_pack := {"allow": true, "deny": set(), "require_approval": true}

silent_pack := {"allow": false, "deny": set(), "require_approval": false}

codes(decision) := {reason.code | some reason in decision.deny}

test_routes_to_allowing_pack if {
	decision := main.decision with input as base_input with data.mcp.packs.github as allowing_pack
	decision.allow == true
	decision.deny == []
	decision.require_approval == false
}

test_decision_carries_policy_version if {
	decision := main.decision with input as base_input with data.mcp.packs.github as allowing_pack
	decision.policy_version == main.policy_version
	is_string(decision.policy_version)
}

test_decision_carries_audit_tags if {
	decision := main.decision with input as base_input with data.mcp.packs.github as allowing_pack
	decision.obligations.audit_tags == ["pack:github", "pack:tag"]
}

test_deny_wins_over_allow if {
	decision := main.decision with input as base_input with data.mcp.packs.github as denying_pack
	decision.allow == false
	codes(decision) == {"github.nope"}
}

test_baseline_deny_wins_over_pack_allow if {
	decision := main.decision with input as base_input
		with data.mcp.packs.github as allowing_pack
		with data.mcp.packs.baseline.deny as {{"code": "baseline.x", "message": "no", "pack": "baseline"}}
	decision.allow == false
	codes(decision) == {"baseline.x"}
}

test_no_allow_rule_is_explained if {
	decision := main.decision with input as base_input with data.mcp.packs.github as silent_pack
	decision.allow == false
	codes(decision) == {"main.no_allow_rule"}
}

test_no_allow_rule_absent_when_something_denied if {
	pack := object.union(denying_pack, {"allow": false})
	decision := main.decision with input as base_input with data.mcp.packs.github as pack
	codes(decision) == {"github.nope"}
}

test_approval_blocks_allow_and_sets_flag if {
	decision := main.decision with input as base_input with data.mcp.packs.github as approving_pack
	decision.allow == false
	decision.require_approval == true
	decision.deny == []
}

test_approval_cannot_override_deny if {
	pack := object.union(denying_pack, {"require_approval": true})
	decision := main.decision with input as base_input with data.mcp.packs.github as pack
	decision.allow == false
	decision.require_approval == false
	codes(decision) == {"github.nope"}
}

test_approval_needs_an_allow if {
	pack := object.union(approving_pack, {"allow": false})
	decision := main.decision with input as base_input with data.mcp.packs.github as pack
	decision.require_approval == false
	codes(decision) == {"main.no_allow_rule"}
}

test_unknown_server_falls_back_to_baseline_allow if {
	unknown := object.union(base_input, {"server": {"name": "wiki"}})
	decision := main.decision with input as unknown with data.mcp.packs.baseline.allow as true
	decision.allow == true
	decision.obligations.audit_tags == ["pack:baseline"]
}

test_unknown_server_denied_by_default if {
	unknown := object.union(base_input, {"server": {"name": "wiki"}})
	decision := main.decision with input as unknown
	decision.allow == false
	codes(decision) == {"main.no_allow_rule"}
}

test_baseline_allow_does_not_apply_to_routed_server if {
	decision := main.decision with input as base_input
		with data.mcp.packs.github as silent_pack
		with data.mcp.packs.baseline.allow as true
	decision.allow == false
}

test_alias_routes_to_pack if {
	aliased := object.union(base_input, {"server": {"name": "gh-prod"}})
	decision := main.decision with input as aliased
		with data.mcp.packs.github as allowing_pack
		with data.mcp_config.main.server_aliases as {"gh-prod": "github"}
	decision.allow == true
}

test_alias_to_unroutable_pack_is_ignored if {
	aliased := object.union(base_input, {"server": {"name": "x"}})
	decision := main.decision with input as aliased
		with data.mcp.packs.lib as allowing_pack
		with data.mcp_config.main.server_aliases as {"x": "lib"}
	decision.allow == false
}

test_aliased_name_cannot_also_route_directly if {
	decision := main.decision with input as base_input
		with data.mcp.packs.github as allowing_pack
		with data.mcp_config.main.server_aliases as {"github": "not-a-pack"}
	decision.allow == false
}

test_server_named_baseline_is_not_routed if {
	named := object.union(base_input, {"server": {"name": "baseline"}})
	decision := main.decision with input as named with data.mcp.packs.baseline.deny as set()
	decision.allow == false
	codes(decision) == {"main.no_allow_rule"}
}

test_server_name_cannot_traverse_packages if {
	named := object.union(base_input, {"server": {"name": "../lib"}})
	decision := main.decision with input as named
	decision.allow == false
}

test_every_routable_pack_is_a_string if {
	every pack in main.routable_packs {
		is_string(pack)
		pack != "baseline"
	}
}

test_empty_input_is_denied if {
	decision := main.decision with input as {}
	decision.allow == false
	decision.require_approval == false
	"main.invalid_input" in codes(decision)
}

test_missing_input_is_denied if {
	decision := main.decision
	decision.allow == false
	"main.invalid_input" in codes(decision)
}

invalid_inputs := {
	"non-object input": "not an object",
	"missing version": object.remove(base_input, ["version"]),
	"numeric version": object.union(base_input, {"version": 1}),
	"missing principal": object.remove(base_input, ["principal"]),
	"empty principal id": object.union(base_input, {"principal": {"id": "", "type": "user"}}),
	"missing server": object.remove(base_input, ["server"]),
	"empty server name": object.union(base_input, {"server": {"name": ""}}),
	"numeric server name": object.union(base_input, {"server": {"name": 7}}),
	"missing tool": object.remove(base_input, ["tool"]),
	"empty tool name": object.union(base_input, {"tool": {"name": ""}}),
	"missing arguments": object.remove(base_input, ["arguments"]),
	"list arguments": object.union(base_input, {"arguments": []}),
}

test_invalid_inputs_are_denied_even_when_pack_allows if {
	every label, value in invalid_inputs {
		decision := main.decision with input as value with data.mcp.packs.github as allowing_pack
		decision.allow == false
		"main.invalid_input" in codes(decision)
		is_string(label)
	}
}

test_unsupported_major_version_is_denied if {
	versioned := object.union(base_input, {"version": "2.0"})
	decision := main.decision with input as versioned with data.mcp.packs.github as allowing_pack
	decision.allow == false
	codes(decision) == {"main.unsupported_input_version"}
}

test_future_minor_version_is_accepted if {
	versioned := object.union(base_input, {"version": "1.7"})
	decision := main.decision with input as versioned with data.mcp.packs.github as allowing_pack
	decision.allow == true
}

scenarios := {
	"allow": allowing_pack,
	"deny": denying_pack,
	"approve": approving_pack,
	"silent": silent_pack,
}

test_decision_invariants_hold if {
	every _, pack in scenarios {
		decision := main.decision with input as base_input with data.mcp.packs.github as pack
		invariants_hold(decision)
	}
}

invariants_hold(decision) if {
	not refused_without_reason(decision)
	not allowed_with_reason(decision)
	not approval_with_allow(decision)
	not approval_with_deny(decision)
}

refused_without_reason(decision) if {
	decision.allow == false
	decision.require_approval == false
	count(decision.deny) == 0
}

allowed_with_reason(decision) if {
	decision.allow == true
	count(decision.deny) > 0
}

approval_with_allow(decision) if {
	decision.require_approval == true
	decision.allow == true
}

approval_with_deny(decision) if {
	decision.require_approval == true
	count(decision.deny) > 0
}
