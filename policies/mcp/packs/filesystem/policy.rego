# METADATA
# title: Filesystem pack
# description: Keeps reads and writes inside configured directories, for the MCP reference filesystem server.
package mcp.packs.filesystem

import data.mcp.lib

pack_name := "filesystem"

default config := {}

config := data.mcp_config.filesystem

# The kind of value each documented key must hold.
config_kinds := {
	"read_paths": "string_list",
	"write_paths": "string_list",
	"deny_globs": "string_list",
	"require_approval_for_writes": "boolean",
}

default read_paths := []

read_paths := config.read_paths

default write_paths := []

write_paths := config.write_paths

default deny_globs := []

deny_globs := config.deny_globs

default tool_name := "<missing>"

tool_name := input.tool.name

# Which arguments hold paths, and the access each one needs.
tools := {
	"read_file": {"read": ["path"]},
	"read_text_file": {"read": ["path"]},
	"read_media_file": {"read": ["path"]},
	"read_multiple_files": {"read_list": "paths"},
	"list_directory": {"read": ["path"]},
	"list_directory_with_sizes": {"read": ["path"]},
	"directory_tree": {"read": ["path"]},
	"get_file_info": {"read": ["path"]},
	"search_files": {"read": ["path"], "strings": ["pattern"]},
	"write_file": {"write": ["path"]},
	"append_file": {"write": ["path"]},
	"edit_file": {"write": ["path"]},
	"create_directory": {"write": ["path"]},
	"move_file": {"write": ["source", "destination"]},
	"copy_file": {"read": ["source"], "write": ["destination"]},
}

# Takes no path, so it is handled apart from the table above.
listing_tools := {"list_allowed_directories"}

spec := tools[tool_name]

read_targets contains value if {
	some arg in spec.read
	value := input.arguments[arg]
}

read_targets contains value if some value in input.arguments[spec.read_list]

write_targets contains value if {
	some arg in spec.write
	value := input.arguments[arg]
}

targets := read_targets | write_targets

string_targets contains target if {
	some target in targets
	is_string(target)
}

required_strings contains arg if some arg in spec.read

required_strings contains arg if some arg in spec.write

required_strings contains arg if some arg in spec.strings

path_list_is_valid if {
	paths := input.arguments[spec.read_list]
	is_array(paths)
	count(paths) > 0
	every path in paths {
		is_string(path)
	}
}

argument_is_string(arg) if is_string(input.arguments[arg])

has_missing_argument if {
	some arg in required_strings
	not argument_is_string(arg)
}

has_missing_argument if {
	spec.read_list
	not path_list_is_valid
}

path_is_malformed(path) if lib.path_has_invalid_chars(path)

path_is_malformed(path) if lib.path_has_indirection(path)

# A config value of the wrong type refuses every call to this pack, instead of quietly
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
	"tool_not_supported",
	sprintf("tool %q is not known to this pack", [tool_name]),
) if {
	not tool_name in object.keys(tools)
	not tool_name in listing_tools
}

deny contains lib.deny_reason(
	pack_name,
	"missing_argument",
	sprintf("tool %q was called without its required path arguments, or with the wrong types", [tool_name]),
) if {
	has_missing_argument
}

deny contains lib.deny_reason(
	pack_name,
	"path_not_absolute",
	sprintf("path %q must be absolute; relative and home-relative paths are ambiguous", [path]),
) if {
	some path in string_targets
	not lib.path_is_absolute(path)
}

deny contains lib.deny_reason(
	pack_name,
	"path_traversal",
	sprintf("path %q contains a traversal sequence", [path]),
) if {
	some path in string_targets
	lib.path_has_traversal(path)
}

deny contains lib.deny_reason(
	pack_name,
	"path_traversal",
	"search pattern contains a traversal sequence",
) if {
	some arg in spec.strings
	lib.path_has_traversal(input.arguments[arg])
}

deny contains lib.deny_reason(
	pack_name,
	"invalid_path",
	sprintf("path %q contains control characters or a kernel link", [path]),
) if {
	some path in string_targets
	path_is_malformed(path)
}

deny contains lib.deny_reason(
	pack_name,
	"path_not_allowed",
	sprintf("path %q is outside the configured read paths", [path]),
) if {
	some path in read_targets
	lib.path_is_safe(path)
	not lib.path_within_any(path, read_paths)
}

deny contains lib.deny_reason(
	pack_name,
	"path_not_allowed",
	sprintf("path %q is outside the configured write paths", [path]),
) if {
	some path in write_targets
	lib.path_is_safe(path)
	not lib.path_within_any(path, write_paths)
}

deny contains lib.deny_reason(
	pack_name,
	"path_denied",
	sprintf("path %q matches a configured deny pattern", [path]),
) if {
	some path in string_targets
	lib.path_matches_any_glob(path, deny_globs)
}

default allow := false

allow if {
	spec
	not has_missing_argument
	every path in read_targets {
		lib.path_within_any(path, read_paths)
	}
	every path in write_targets {
		lib.path_within_any(path, write_paths)
	}
	count(deny) == 0
}

allow if {
	tool_name in listing_tools
	is_array(read_paths)
	count(read_paths) > 0
	count(deny) == 0
}

default require_approval := false

require_approval if {
	lib.flag_enabled(config, "require_approval_for_writes")
	count(spec.write) > 0
}

audit_tags contains "filesystem:read" if count(spec.read) > 0

audit_tags contains "filesystem:read" if spec.read_list

audit_tags contains "filesystem:read" if tool_name in listing_tools

audit_tags contains "filesystem:write" if count(spec.write) > 0
