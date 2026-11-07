# METADATA
# title: Baseline pack
# description: Applies to every tool call. Its allow rule is used only for servers with no pack of their own.
package mcp.packs.baseline

import data.mcp.lib

pack_name := "baseline"

default config := {}

config := data.mcp_config.baseline

# The kind of value each documented key must hold.
config_kinds := {
	"allowed_servers": "string_list",
	"allowed_tools": "string_list_map",
	"destructive_allowlist": "string_list_map",
	"business_hours": "object",
}

default server_name := "<missing>"

server_name := input.server.name

default tool_name := "<missing>"

tool_name := input.tool.name

default timestamp := ""

timestamp := input.timestamp

default allow := false

allow if {
	count(config_problems) == 0
	tool_name in config.allowed_tools[server_name]
}

destructive_allowlisted if tool_name in config.destructive_allowlist[server_name]

# A config value of the wrong type refuses every call, since baseline applies to all of them, instead of quietly
# switching a check off.
config_problems := lib.config_problems(config, config_kinds)

deny contains lib.deny_reason(
	pack_name,
	"invalid_config",
	sprintf("the %s configuration is invalid: %s", [pack_name, concat("; ", sort(config_problems))]),
) if {
	count(config_problems) > 0
}

deny contains lib.deny_reason(
	pack_name,
	"server_not_allowed",
	sprintf("server %q is not in the allowed server list", [server_name]),
) if {
	"allowed_servers" in object.keys(config)
	not server_name in config.allowed_servers
}

# Fires only on an explicit hint. A hint that is present but not false counts as destructive.
deny contains lib.deny_reason(
	pack_name,
	"destructive_tool",
	sprintf("tool %q on server %q is marked destructive and is not allowlisted", [tool_name, server_name]),
) if {
	input.tool.annotations.destructiveHint != false
	not destructive_allowlisted
}

deny contains lib.deny_reason(
	pack_name,
	"invalid_timestamp",
	"a business-hours window is configured but the input timestamp is missing or invalid",
) if {
	"business_hours" in object.keys(config)
	not lib.timestamp_is_valid(timestamp)
}

deny contains lib.deny_reason(
	pack_name,
	"outside_business_hours",
	sprintf("tool calls are allowed only inside the configured window; the call was at %s", [timestamp]),
) if {
	lib.timestamp_is_valid(timestamp)
	window := config.business_hours
	not lib.window_contains(timestamp, window)
}
