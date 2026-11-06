package mcp.packs.filesystem_test

import data.mcp.packs.filesystem

config := {
	"read_paths": ["/srv/app"],
	"write_paths": ["/srv/app/tmp"],
	"deny_globs": ["**/.env", "**/.ssh/**"],
}

call(tool, arguments) := {
	"version": "1.0",
	"principal": {"id": "alice", "type": "user"},
	"server": {"name": "filesystem"},
	"tool": {"name": tool},
	"arguments": arguments,
}

codes(reasons) := {reason.code | some reason in reasons}

read_tools := {
	"read_file",
	"read_text_file",
	"read_media_file",
	"list_directory",
	"list_directory_with_sizes",
	"directory_tree",
	"get_file_info",
}

write_tools := {"write_file", "append_file", "edit_file", "create_directory"}

# Allow cases.

test_every_read_tool_allowed_inside_read_path if {
	every tool in read_tools {
		filesystem.allow with input as call(tool, {"path": "/srv/app/a.txt"}) with data.mcp_config.filesystem as config
	}
}

test_every_write_tool_allowed_inside_write_path if {
	every tool in write_tools {
		filesystem.allow with input as call(tool, {"path": "/srv/app/tmp/a.txt"}) with data.mcp_config.filesystem as config
	}
}

test_read_multiple_files_allowed if {
	args := {"paths": ["/srv/app/a", "/srv/app/b"]}
	filesystem.allow with input as call("read_multiple_files", args) with data.mcp_config.filesystem as config
}

test_config_without_write_paths_allows_reads_only if {
	read_only := {"read_paths": ["/srv/app"]}
	filesystem.allow with input as call("read_text_file", {"path": "/srv/app/a"}) with data.mcp_config.filesystem as read_only
	not filesystem.allow with input as call("write_file", {"path": "/srv/app/a"}) with data.mcp_config.filesystem as read_only
	reasons := filesystem.deny with input as call("write_file", {"path": "/srv/app/a"}) with data.mcp_config.filesystem as read_only
	"filesystem.path_not_allowed" in codes(reasons)
}

test_search_files_allowed if {
	args := {"path": "/srv/app", "pattern": "**/*.go"}
	filesystem.allow with input as call("search_files", args) with data.mcp_config.filesystem as config
}

test_move_inside_write_path_allowed if {
	args := {"source": "/srv/app/tmp/a", "destination": "/srv/app/tmp/b"}
	filesystem.allow with input as call("move_file", args) with data.mcp_config.filesystem as config
}

test_copy_from_read_to_write_allowed if {
	args := {"source": "/srv/app/a", "destination": "/srv/app/tmp/b"}
	filesystem.allow with input as call("copy_file", args) with data.mcp_config.filesystem as config
}

test_list_allowed_directories_needs_read_paths if {
	filesystem.allow with input as call("list_allowed_directories", {}) with data.mcp_config.filesystem as config
	not filesystem.allow with input as call("list_allowed_directories", {})
}

test_normalized_path_inside_allowed if {
	filesystem.allow with input as call("read_text_file", {"path": "/srv//app/./a"}) with data.mcp_config.filesystem as config
}

# Read and write separation.

test_read_path_does_not_grant_write if {
	reasons := filesystem.deny with input as call("write_file", {"path": "/srv/app/a"}) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_not_allowed"}
}

test_write_path_does_not_grant_read if {
	cfg := {"write_paths": ["/data"]}
	reasons := filesystem.deny with input as call("read_text_file", {"path": "/data/a"}) with data.mcp_config.filesystem as cfg
	codes(reasons) == {"filesystem.path_not_allowed"}
}

test_move_source_needs_write if {
	args := {"source": "/srv/app/a", "destination": "/srv/app/tmp/b"}
	reasons := filesystem.deny with input as call("move_file", args) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_not_allowed"}
}

test_move_destination_needs_write if {
	args := {"source": "/srv/app/tmp/a", "destination": "/srv/app/b"}
	not filesystem.allow with input as call("move_file", args) with data.mcp_config.filesystem as config
}

test_copy_source_needs_read if {
	args := {"source": "/etc/passwd", "destination": "/srv/app/tmp/b"}
	reasons := filesystem.deny with input as call("copy_file", args) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_not_allowed"}
}

test_copy_destination_needs_write if {
	args := {"source": "/srv/app/a", "destination": "/srv/app/b"}
	not filesystem.allow with input as call("copy_file", args) with data.mcp_config.filesystem as config
}

test_edit_dry_run_still_needs_write if {
	args := {"path": "/srv/app/a", "edits": [], "dryRun": true}
	not filesystem.allow with input as call("edit_file", args) with data.mcp_config.filesystem as config
}

# Path allowlist and traversal.

test_outside_allowed_path_denied if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": "/etc/passwd"}) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_not_allowed"}
}

test_sibling_with_shared_prefix_denied if {
	not filesystem.allow with input as call("read_text_file", {"path": "/srv/app-secrets/a"}) with data.mcp_config.filesystem as config
}

test_traversal_denied if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": "/srv/app/../../etc/passwd"}) with data.mcp_config.filesystem as config
	"filesystem.path_traversal" in codes(reasons)
	not filesystem.allow with input as call("read_text_file", {"path": "/srv/app/../../etc/passwd"}) with data.mcp_config.filesystem as config
}

test_encoded_traversal_denied if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": "/srv/app/%2e%2e/secret"}) with data.mcp_config.filesystem as config
	"filesystem.path_traversal" in codes(reasons)
}

test_backslash_traversal_denied if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": `/srv/app\..\secret`}) with data.mcp_config.filesystem as config
	"filesystem.path_traversal" in codes(reasons)
}

test_relative_path_denied if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": "srv/app/a"}) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_not_absolute"}
}

test_home_path_denied if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": "~/.bashrc"}) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_not_absolute"}
}

test_empty_path_denied if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": ""}) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_not_absolute"}
}

test_control_character_denied if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": "/srv/app/a\u0000.txt"}) with data.mcp_config.filesystem as config
	"filesystem.invalid_path" in codes(reasons)
	not filesystem.allow with input as call("read_text_file", {"path": "/srv/app/a\u0000.txt"}) with data.mcp_config.filesystem as config
}

test_proc_link_denied_even_when_root_allowed if {
	cfg := {"read_paths": ["/"]}
	reasons := filesystem.deny with input as call("read_text_file", {"path": "/proc/self/root/etc/passwd"}) with data.mcp_config.filesystem as cfg
	"filesystem.invalid_path" in codes(reasons)
	not filesystem.allow with input as call("read_text_file", {"path": "/proc/self/root/etc/passwd"}) with data.mcp_config.filesystem as cfg
}

test_every_path_in_list_is_checked if {
	args := {"paths": ["/srv/app/a", "/etc/passwd"]}
	reasons := filesystem.deny with input as call("read_multiple_files", args) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_not_allowed"}
	not filesystem.allow with input as call("read_multiple_files", args) with data.mcp_config.filesystem as config
}

test_search_pattern_traversal_denied if {
	args := {"path": "/srv/app", "pattern": "../../**"}
	reasons := filesystem.deny with input as call("search_files", args) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_traversal"}
	not filesystem.allow with input as call("search_files", args) with data.mcp_config.filesystem as config
}

# Deny globs.

test_deny_glob_blocks_inside_allowed_path if {
	reasons := filesystem.deny with input as call("read_text_file", {"path": "/srv/app/.env"}) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.path_denied"}
	not filesystem.allow with input as call("read_text_file", {"path": "/srv/app/.env"}) with data.mcp_config.filesystem as config
}

test_deny_glob_is_case_insensitive if {
	not filesystem.allow with input as call("read_text_file", {"path": "/srv/app/.ENV"}) with data.mcp_config.filesystem as config
}

test_deny_glob_blocks_listing_the_directory if {
	not filesystem.allow with input as call("list_directory", {"path": "/srv/app/.ssh"}) with data.mcp_config.filesystem as config
}

test_deny_glob_applies_to_writes if {
	not filesystem.allow with input as call("write_file", {"path": "/srv/app/tmp/.env", "content": "x"}) with data.mcp_config.filesystem as config
}

# Default deny and unknown tools.

test_no_config_denies if {
	not filesystem.allow with input as call("read_text_file", {"path": "/srv/app/a"})
	codes(filesystem.deny) == {"filesystem.path_not_allowed"} with input as call("read_text_file", {"path": "/srv/app/a"})
}

test_unknown_tool_denied if {
	reasons := filesystem.deny with input as call("delete_everything", {"path": "/srv/app/a"}) with data.mcp_config.filesystem as config
	codes(reasons) == {"filesystem.tool_not_supported"}
	not filesystem.allow with input as call("delete_everything", {"path": "/srv/app/a"}) with data.mcp_config.filesystem as config
}

test_annotations_never_grant if {
	annotated := object.union(call("read_text_file", {"path": "/etc/passwd"}), {"tool": {"annotations": {"readOnlyHint": true}}})
	not filesystem.allow with input as annotated with data.mcp_config.filesystem as config
}

test_mistyped_config_grants_nothing if {
	cfg := {"read_paths": "/srv/app"}
	not filesystem.allow with input as call("read_text_file", {"path": "/srv/app/a"}) with data.mcp_config.filesystem as cfg
}

# Missing fields and unexpected types.

malformed_calls := {
	"empty arguments": call("read_text_file", {}),
	"numeric path": call("read_text_file", {"path": 42}),
	"null path": call("read_text_file", {"path": null}),
	"list as path": call("read_text_file", {"path": ["/srv/app/a"]}),
	"no paths": call("read_multiple_files", {}),
	"empty paths": call("read_multiple_files", {"paths": []}),
	"string paths": call("read_multiple_files", {"paths": "/srv/app/a"}),
	"mixed paths": call("read_multiple_files", {"paths": ["/srv/app/a", 42]}),
	"no destination": call("move_file", {"source": "/srv/app/tmp/a"}),
	"no source": call("copy_file", {"destination": "/srv/app/tmp/a"}),
	"no search pattern": call("search_files", {"path": "/srv/app"}),
	"numeric search pattern": call("search_files", {"path": "/srv/app", "pattern": 1}),
}

test_malformed_arguments_denied if {
	every label, malformed in malformed_calls {
		is_string(label)
		not filesystem.allow with input as malformed with data.mcp_config.filesystem as config
		reasons := filesystem.deny with input as malformed with data.mcp_config.filesystem as config
		"filesystem.missing_argument" in codes(reasons)
	}
}

test_missing_tool_name_denied if {
	not filesystem.allow with input as {"arguments": {}} with data.mcp_config.filesystem as config
	codes(filesystem.deny) == {"filesystem.tool_not_supported"} with input as {"arguments": {}}
		with data.mcp_config.filesystem as config
}

# Approval and audit.

test_write_needs_approval_when_configured if {
	cfg := object.union(config, {"require_approval_for_writes": true})
	filesystem.require_approval with input as call("write_file", {"path": "/srv/app/tmp/a"}) with data.mcp_config.filesystem as cfg
}

test_read_never_needs_approval if {
	cfg := object.union(config, {"require_approval_for_writes": true})
	not filesystem.require_approval with input as call("read_text_file", {"path": "/srv/app/a"}) with data.mcp_config.filesystem as cfg
}

test_approval_flag_must_be_literal_true if {
	cfg := object.union(config, {"require_approval_for_writes": "true"})
	not filesystem.require_approval with input as call("write_file", {"path": "/srv/app/tmp/a"}) with data.mcp_config.filesystem as cfg
}

test_audit_tags if {
	filesystem.audit_tags == {"filesystem:read"} with input as call("read_text_file", {"path": "/a"})
	filesystem.audit_tags == {"filesystem:write"} with input as call("write_file", {"path": "/a"})
	filesystem.audit_tags == {"filesystem:read", "filesystem:write"} with input as call("copy_file", {"source": "/a", "destination": "/b"})
	filesystem.audit_tags == {"filesystem:read"} with input as call("read_multiple_files", {"paths": ["/a"]})
	filesystem.audit_tags == {"filesystem:read"} with input as call("list_allowed_directories", {})
}

test_path_list_given_as_object_denied if {
	request := call("read_multiple_files", {"paths": {"a": "/srv/app/a"}})
	not filesystem.allow with input as request with data.mcp_config.filesystem as config
	reasons := filesystem.deny with input as request with data.mcp_config.filesystem as config
	"filesystem.missing_argument" in codes(reasons)
}

test_listing_needs_read_paths_as_a_list if {
	not filesystem.allow with input as call("list_allowed_directories", {}) with data.mcp_config.filesystem as {"read_paths": "/srv/app"}
}
