# METADATA
# title: GitHub pack
# description: Repo allowlist, protected branches and paths, and guarded operations for the GitHub MCP server.
package mcp.packs.github

import data.mcp.lib

pack_name := "github"

default config := {}

config := data.mcp_config.github

# The kind of value each documented key must hold.
config_kinds := {
	"allowed_repos": "string_list",
	"allowed_orgs": "string_list",
	"protected_branches": "string_list",
	"protected_paths": "string_list",
	"require_approval_tools": "string_list",
	"allow_merge": "boolean",
	"allow_update_pr_branch": "boolean",
	"allow_workflow_runs": "boolean",
	"allow_copilot": "boolean",
	"allow_secret_alerts": "boolean",
	"allow_global_read": "boolean",
	"allow_pr_approval": "boolean",
	"require_approval_for_writes": "boolean",
}

default protected_branches := ["main", "master"]

protected_branches := config.protected_branches

default protected_paths := [".github/workflows/**", ".github/actions/**"]

protected_paths := config.protected_paths

default allowed_repos := []

allowed_repos := config.allowed_repos

default allowed_orgs := []

allowed_orgs := config.allowed_orgs

default tool_name := "<missing>"

tool_name := input.tool.name

default owner := null

owner := input.arguments.owner

default repo := null

repo := input.arguments.repo

default parent_owner := null

parent_owner := input.arguments.parent_owner

default parent_repo := null

parent_repo := input.arguments.parent_repo

default branch := null

branch := input.arguments.branch

review_methods := {"create", "submit_pending", "delete_pending"}

repo_tools := (repo_read_tools | repo_write_tools) | object.keys(gated_tools)

write_tools := repo_write_tools | {name | some name, gate in gated_tools; gate.write == true}

known_tools := ((repo_tools | global_read_tools) | admin_tools) | {"delete_repository"}

allowed_repo_set := lib.lower_set(allowed_repos)

allowed_org_set := lib.lower_set(allowed_orgs)

name_is_valid(name) if {
	is_string(name)
	regex.match(`^[A-Za-z0-9_.-]+$`, name)
	not name in {".", ".."}
}

repo_is_allowed(repo_owner, repo_name) if {
	name_is_valid(repo_owner)
	name_is_valid(repo_name)
	lower(sprintf("%s/%s", [repo_owner, repo_name])) in allowed_repo_set
}

repo_is_allowed(repo_owner, repo_name) if {
	name_is_valid(repo_owner)
	name_is_valid(repo_name)
	lower(repo_owner) in allowed_org_set
}

has_parent_reference if "parent_owner" in object.keys(input.arguments)

has_parent_reference if "parent_repo" in object.keys(input.arguments)

argument_is_string(name) if is_string(input.arguments[name])

normalized_branch(name) := lower(trim_prefix(trim_prefix(name, "refs/heads/"), "heads/"))

# A deliberately strict subset of what git allows. Anything else is refused.
branch_is_valid(name) if {
	is_string(name)
	regex.match(`^[A-Za-z0-9._/#+=@-]+$`, name)
	not contains(name, "..")
	not contains(name, "//")
	not startswith(name, "/")
	not endswith(name, "/")
	not startswith(normalized_branch(name), "refs/")
}

branch_is_protected(name) if {
	some pattern in protected_branches
	glob.match(lower(pattern), ["/"], normalized_branch(name))
}

# A pull request from a protected branch would let update_pull_request_branch, or a merge
# in the other direction, write to that branch.
pull_request_head_branch := branch_part if {
	tool_name == "create_pull_request"
	head := input.arguments.head
	is_string(head)
	parts := split(head, ":")
	branch_part := parts[count(parts) - 1]
}

repo_paths contains path if {
	tool_name in single_path_tools
	path := input.arguments.path
}

repo_paths contains path if {
	tool_name == "push_files"
	some file in input.arguments.files
	path := file.path
}

repo_paths_are_present if {
	tool_name in single_path_tools
	argument_is_string("path")
}

repo_paths_are_present if {
	tool_name == "push_files"
	files := input.arguments.files
	is_array(files)
	count(files) > 0
	every file in files {
		is_string(file.path)
	}
}

repo_path_is_unsafe(path) if lib.path_has_traversal(path)

repo_path_is_unsafe(path) if lib.path_has_invalid_chars(path)

# The server builds the request URL from the path without escaping it, so GitHub decodes any
# percent escape, and reads "?" and "#" as the end of the path. The file that is written is
# then not the one checked here: ".%67ithub/workflows/ci.yml" lands in .github/workflows.
repo_path_is_unsafe(path) if regex.match(`[%?#]`, path)

repo_path_is_protected(path) if {
	canonical := lower(concat("/", lib.path_segments(path)))
	some pattern in protected_paths
	glob.match(lower(pattern), ["/"], canonical)
}

review_method_is_allowed if input.arguments.method in review_methods

# The server's other events. Anything else, including APPROVE with stray whitespace, needs the flag.
review_events_without_approval := {"COMMENT", "REQUEST_CHANGES"}

review_event_is_present if "event" in object.keys(input.arguments)

review_event_is_allowed if not review_event_is_present

review_event_is_allowed if lib.flag_enabled(config, "allow_pr_approval")

review_event_is_allowed if {
	event := input.arguments.event
	is_string(event)
	upper(event) in review_events_without_approval
}

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
	"repo_deletion",
	"deleting a repository is never allowed",
) if {
	tool_name == "delete_repository"
}

deny contains lib.deny_reason(
	pack_name,
	"admin_operation",
	sprintf("tool %q changes repository or organization administration", [tool_name]),
) if {
	tool_name in admin_tools
}

deny contains lib.deny_reason(
	pack_name,
	"tool_not_supported",
	sprintf("tool %q is not known to this pack", [tool_name]),
) if {
	not tool_name in known_tools
}

deny contains lib.deny_reason(
	pack_name,
	gate.code,
	gate.reason,
) if {
	gate := gated_tools[tool_name]
	not lib.flag_enabled(config, gate.flag)
}

deny contains lib.deny_reason(
	pack_name,
	"global_read_not_allowed",
	sprintf("tool %q is not limited to one repository, so the allowlist cannot constrain it", [tool_name]),
) if {
	tool_name in global_read_tools
	not lib.flag_enabled(config, "allow_global_read")
}

deny contains lib.deny_reason(
	pack_name,
	"repo_not_allowed",
	sprintf("repository %v/%v is not in the allowed repositories or organizations", [owner, repo]),
) if {
	tool_name in repo_tools
	not repo_is_allowed(owner, repo)
}

deny contains lib.deny_reason(
	pack_name,
	"repo_not_allowed",
	sprintf("parent repository %v/%v is not in the allowed repositories or organizations", [parent_owner, parent_repo]),
) if {
	tool_name == "issue_write"
	has_parent_reference
	not repo_is_allowed(parent_owner, parent_repo)
}

deny contains lib.deny_reason(
	pack_name,
	"invalid_branch",
	sprintf("branch %v is missing or is not a plain branch name", [branch]),
) if {
	tool_name in branch_tools
	not branch_is_valid(branch)
}

deny contains lib.deny_reason(
	pack_name,
	"protected_branch",
	sprintf("branch %q is protected; open a pull request instead", [branch]),
) if {
	tool_name in branch_tools
	branch_is_valid(branch)
	branch_is_protected(branch)
}

deny contains lib.deny_reason(
	pack_name,
	"protected_branch",
	sprintf(
		"pull request head %q is a protected branch; open pull requests from a working branch",
		[pull_request_head_branch],
	),
) if {
	branch_is_protected(pull_request_head_branch)
}

deny contains lib.deny_reason(
	pack_name,
	"invalid_path",
	sprintf("tool %q was called without valid repository file paths", [tool_name]),
) if {
	tool_name in (single_path_tools | {"push_files"})
	not repo_paths_are_present
}

deny contains lib.deny_reason(
	pack_name,
	"invalid_path",
	sprintf("repository path %q contains a traversal sequence, a control character or one of %%, ? and #", [path]),
) if {
	some path in repo_paths
	repo_path_is_unsafe(path)
}

deny contains lib.deny_reason(
	pack_name,
	"protected_path",
	sprintf("repository path %q is protected", [path]),
) if {
	some path in repo_paths
	is_string(path)
	not repo_path_is_unsafe(path)
	repo_path_is_protected(path)
}

deny contains lib.deny_reason(
	pack_name,
	"symlink_write",
	"writing a symbolic link through this tool is not allowed",
) if {
	tool_name == "create_or_update_file"
	input.arguments.allow_symlink_write != false
}

deny contains lib.deny_reason(
	pack_name,
	"missing_argument",
	sprintf("create_pull_request needs a string %s", [name]),
) if {
	tool_name == "create_pull_request"
	some name in ["base", "head"]
	not argument_is_string(name)
}

deny contains lib.deny_reason(
	pack_name,
	"cross_repo_head",
	sprintf("pull request head owner %q is not this repository's owner or an allowed organization", [head_owner]),
) if {
	tool_name == "create_pull_request"
	head := input.arguments.head
	contains(head, ":")
	head_owner := lower(split(head, ":")[0])
	head_owner != lower(owner)
	not head_owner in allowed_org_set
}

deny contains lib.deny_reason(
	pack_name,
	"review_method_not_allowed",
	"this review method is off; resolve_thread acts on a thread ID the repo allowlist cannot check",
) if {
	tool_name == "pull_request_review_write"
	not review_method_is_allowed
}

deny contains lib.deny_reason(
	pack_name,
	"pr_approval_not_allowed",
	"an agent may not approve a pull request unless allow_pr_approval is set",
) if {
	tool_name == "pull_request_review_write"
	not review_event_is_allowed
}

default allow := false

allow if {
	tool_name in repo_tools
	repo_is_allowed(owner, repo)
	count(deny) == 0
}

allow if {
	tool_name in global_read_tools
	lib.flag_enabled(config, "allow_global_read")
	count(deny) == 0
}

default require_approval := false

require_approval if {
	lib.flag_enabled(config, "require_approval_for_writes")
	tool_name in write_tools
}

require_approval if tool_name in config.require_approval_tools

audit_tags contains "github:write" if tool_name in write_tools

audit_tags contains "github:read" if {
	tool_name in (repo_tools | global_read_tools)
	not tool_name in write_tools
}
