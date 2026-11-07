# METADATA
# title: MCP policy entrypoint
# description: Routes a tool call to its pack, applies baseline to every call and merges results. Deny wins.
package mcp.main

import data.mcp.lib
import data.mcp.packs.baseline

policy_version := "0.1.1"

# Packs a server may route to. Baseline runs on every call and is never a route.
routable_packs := {"filesystem", "github", "postgres"}

default router_config := {}

router_config := data.mcp_config.main

default server_aliases := {}

server_aliases := router_config.server_aliases

# A malformed router config refuses every call.
config_problems := lib.config_problems(router_config, {"server_aliases": "string_map"})

routed_pack := server_aliases[input.server.name] if server_aliases[input.server.name] in routable_packs

routed_pack := server_name if {
	server_name := input.server.name
	not server_name in object.keys(server_aliases)
	server_name in routable_packs
}

is_routed if routed_pack

# The only dynamic reference to a pack. routed_pack is always a member of routable_packs.
# regal ignore:unresolved-reference
pack := data.mcp.packs[routed_pack]

input_is_well_formed if {
	is_string(input.version)
	non_empty_string(input.principal.id)
	non_empty_string(input.server.name)
	non_empty_string(input.tool.name)
	is_object(input.arguments)
}

non_empty_string(value) if {
	is_string(value)
	value != ""
}

input_errors contains lib.deny_reason(
	"main",
	"invalid_input",
	"input is missing a required field: version, principal.id, server.name, tool.name or arguments",
) if {
	not input_is_well_formed
}

input_errors contains lib.deny_reason(
	"main",
	"unsupported_input_version",
	"input version is not supported; this policy reads version 1.x",
) if {
	version := input.version
	is_string(version)
	not regex.match(`^1\.[0-9]+$`, version)
}

explicit_denies contains reason if some reason in input_errors

explicit_denies contains lib.deny_reason(
	"main",
	"invalid_config",
	sprintf("the router configuration is invalid: %s", [concat("; ", sort(config_problems))]),
) if {
	count(config_problems) > 0
}

explicit_denies contains reason if some reason in baseline.deny

explicit_denies contains reason if some reason in pack.deny

default tool_allowed := false

tool_allowed if pack.allow == true

tool_allowed if {
	not is_routed
	baseline.allow == true
}

fallback_denies contains lib.deny_reason("main", "no_allow_rule", "no rule allows this tool call") if {
	count(explicit_denies) == 0
	not tool_allowed
}

denies := explicit_denies | fallback_denies

default approval_pending := false

approval_pending if {
	tool_allowed
	count(denies) == 0
	pack.require_approval == true
}

default allowed := false

allowed if {
	tool_allowed
	count(denies) == 0
	not approval_pending
}

audit_tags contains sprintf("pack:%s", [routed_pack])

audit_tags contains "pack:baseline" if not is_routed

audit_tags contains tag if some tag in pack.audit_tags

# METADATA
# description: The decision for one tool call. Always defined and complete, whatever the input.
# entrypoint: true
decision := {
	"allow": allowed,
	"deny": sort(denies),
	"require_approval": approval_pending,
	"obligations": {"audit_tags": sort(audit_tags)},
	"policy_version": policy_version,
}
