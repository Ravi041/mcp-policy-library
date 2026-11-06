# METADATA
# title: Baseline pack
# description: Applies to every tool call. Its allow rule is used only for servers with no pack of their own.
package mcp.packs.baseline

import data.mcp.lib

pack_name := "baseline"

default config := {}

config := data.mcp_config.baseline

default server_name := "<missing>"

server_name := input.server.name

default tool_name := "<missing>"

tool_name := input.tool.name

default timestamp := ""

timestamp := input.timestamp

default allow := false

allow if tool_name in config.allowed_tools[server_name]

destructive_allowlisted if tool_name in config.destructive_allowlist[server_name]

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
