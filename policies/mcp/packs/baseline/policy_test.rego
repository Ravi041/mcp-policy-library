package mcp.packs.baseline_test

import data.mcp.packs.baseline

call(server, tool) := {
	"version": "1.0",
	"timestamp": "2026-11-05T12:00:00Z",
	"principal": {"id": "alice", "type": "user"},
	"server": {"name": server},
	"tool": {"name": tool},
	"arguments": {},
}

destructive_call := object.union(call("filesystem", "write_file"), {"tool": {"annotations": {"destructiveHint": true}}})

hours := {
	"timezone": "UTC",
	"days": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
	"start": "09:00",
	"end": "17:00",
}

codes(reasons) := {reason.code | some reason in reasons}

# Allow: only the explicit fallback list for servers without a pack.

test_allow_is_false_with_no_config if not baseline.allow with input as call("wiki", "search")

test_allow_for_listed_fallback_tool if {
	baseline.allow with input as call("wiki", "search")
		with data.mcp_config.baseline.allowed_tools as {"wiki": ["search"]}
}

test_allow_is_false_for_unlisted_tool if {
	not baseline.allow with input as call("wiki", "delete_page")
		with data.mcp_config.baseline.allowed_tools as {"wiki": ["search"]}
}

test_allow_is_false_for_other_server if {
	not baseline.allow with input as call("other", "search")
		with data.mcp_config.baseline.allowed_tools as {"wiki": ["search"]}
}

test_allow_list_with_wrong_type_grants_nothing if {
	not baseline.allow with input as call("wiki", "search")
		with data.mcp_config.baseline.allowed_tools as {"wiki": "search"}
}

test_read_only_annotation_never_grants if {
	annotated := object.union(call("wiki", "search"), {"tool": {"annotations": {"readOnlyHint": true}}})
	not baseline.allow with input as annotated
}

# Server allowlist.

test_no_server_restriction_when_unconfigured if count(baseline.deny) == 0 with input as call("anything", "t")

test_listed_server_passes if {
	count(baseline.deny) == 0 with input as call("github", "t")
		with data.mcp_config.baseline.allowed_servers as ["github"]
}

test_unlisted_server_denied if {
	reasons := baseline.deny with input as call("evil", "t")
		with data.mcp_config.baseline.allowed_servers as ["github"]
	codes(reasons) == {"baseline.server_not_allowed"}
}

test_empty_server_list_denies_everything if {
	reasons := baseline.deny with input as call("github", "t")
		with data.mcp_config.baseline.allowed_servers as []
	codes(reasons) == {"baseline.server_not_allowed"}
}

test_server_list_denial_survives_missing_server_name if {
	reasons := baseline.deny with input as {}
		with data.mcp_config.baseline.allowed_servers as ["github"]
	codes(reasons) == {"baseline.server_not_allowed"}
}

# Destructive tools.

test_destructive_tool_denied if {
	reasons := baseline.deny with input as destructive_call
	codes(reasons) == {"baseline.destructive_tool"}
}

test_destructive_tool_allowlisted if {
	count(baseline.deny) == 0 with input as destructive_call
		with data.mcp_config.baseline.destructive_allowlist as {"filesystem": ["write_file"]}
}

test_allowlist_is_per_server if {
	reasons := baseline.deny with input as destructive_call
		with data.mcp_config.baseline.destructive_allowlist as {"github": ["write_file"]}
	codes(reasons) == {"baseline.destructive_tool"}
}

test_allowlist_is_per_tool if {
	reasons := baseline.deny with input as destructive_call
		with data.mcp_config.baseline.destructive_allowlist as {"filesystem": ["edit_file"]}
	codes(reasons) == {"baseline.destructive_tool"}
}

test_explicit_false_hint_is_not_destructive if {
	safe := object.union(call("s", "t"), {"tool": {"annotations": {"destructiveHint": false}}})
	count(baseline.deny) == 0 with input as safe
}

test_missing_hint_is_not_marked_destructive if count(baseline.deny) == 0 with input as call("s", "t")

test_non_boolean_hint_fails_closed if {
	odd := object.union(call("s", "t"), {"tool": {"annotations": {"destructiveHint": "false"}}})
	codes(baseline.deny) == {"baseline.destructive_tool"} with input as odd
}

test_read_only_hint_does_not_excuse_destructive_hint if {
	odd := object.union(destructive_call, {"tool": {"annotations": {"readOnlyHint": true}}})
	codes(baseline.deny) == {"baseline.destructive_tool"} with input as odd
}

# Business hours.

test_inside_business_hours if {
	count(baseline.deny) == 0 with input as call("s", "t")
		with data.mcp_config.baseline.business_hours as hours
}

test_outside_business_hours if {
	late := object.union(call("s", "t"), {"timestamp": "2026-11-05T20:00:00Z"})
	codes(baseline.deny) == {"baseline.outside_business_hours"} with input as late
		with data.mcp_config.baseline.business_hours as hours
}

test_missing_timestamp_fails_closed if {
	missing := object.remove(call("s", "t"), ["timestamp"])
	codes(baseline.deny) == {"baseline.invalid_timestamp"} with input as missing
		with data.mcp_config.baseline.business_hours as hours
}

test_malformed_timestamp_fails_closed if {
	bad := object.union(call("s", "t"), {"timestamp": "noon"})
	codes(baseline.deny) == {"baseline.invalid_timestamp"} with input as bad
		with data.mcp_config.baseline.business_hours as hours
}

test_misconfigured_window_fails_closed if {
	codes(baseline.deny) == {"baseline.outside_business_hours"} with input as call("s", "t")
		with data.mcp_config.baseline.business_hours as object.remove(hours, ["timezone"])
}

test_hours_ignored_when_unconfigured if {
	late := object.union(call("s", "t"), {"timestamp": "2026-11-05T20:00:00Z"})
	count(baseline.deny) == 0 with input as late
}
