package mcp.packs.github_test

import data.mcp.packs.github

config := {
	"allowed_repos": ["acme/web"],
	"allowed_orgs": ["trusted-org"],
	"protected_branches": ["main", "master", "release/*"],
}

repo_args := {"owner": "acme", "repo": "web"}

call(tool, arguments) := {
	"version": "1.0",
	"principal": {"id": "alice", "type": "user"},
	"server": {"name": "github"},
	"tool": {"name": tool},
	"arguments": arguments,
}

repo_call(tool, extra) := call(tool, object.union(repo_args, extra))

codes(reasons) := {reason.code | some reason in reasons}

allowed(request) if github.allow with input as request with data.mcp_config.github as config

denied_with(request, code) if {
	not allowed(request)
	code in codes(github.deny) with input as request with data.mcp_config.github as config
}

pr := {"title": "t", "head": "feature/x", "base": "main"}

file_write := {"branch": "feature/x", "path": "src/a.go", "content": "x", "message": "m"}

# Allow cases.

test_open_pull_request_into_main_allowed if allowed(repo_call("create_pull_request", pr))

test_read_tools_allowed_on_listed_repo if {
	every tool in {"get_file_contents", "list_branches", "pull_request_read", "list_issues", "get_commit"} {
		allowed(repo_call(tool, {}))
	}
}

test_push_to_feature_branch_allowed if {
	allowed(repo_call("push_files", {"branch": "feature/x", "message": "m", "files": [{"path": "a", "content": "x"}]}))
}

test_create_or_update_file_on_feature_branch_allowed if allowed(repo_call("create_or_update_file", file_write))

test_create_branch_from_main_allowed if allowed(repo_call("create_branch", {"branch": "feature/x", "from_branch": "main"}))

test_issue_write_allowed if allowed(repo_call("issue_write", {"method": "create", "title": "t"}))

test_repo_in_allowed_org_allowed if allowed(call("list_branches", {"owner": "trusted-org", "repo": "anything"}))

test_owner_and_repo_match_case_insensitively if allowed(call("list_branches", {"owner": "ACME", "repo": "Web"}))

# Repository allowlist.

test_unlisted_repo_denied if denied_with(call("list_branches", {"owner": "acme", "repo": "other"}), "github.repo_not_allowed")

test_unlisted_owner_denied if denied_with(call("get_file_contents", {"owner": "evil", "repo": "web"}), "github.repo_not_allowed")

test_no_config_denies_everything if {
	request := repo_call("create_pull_request", pr)
	not github.allow with input as request
	"github.repo_not_allowed" in codes(github.deny) with input as request
}

test_path_like_owner_denied if denied_with(call("list_branches", {"owner": "trusted-org/../evil", "repo": "x"}), "github.repo_not_allowed")

test_dot_dot_repo_denied if denied_with(call("list_branches", {"owner": "trusted-org", "repo": ".."}), "github.repo_not_allowed")

test_missing_owner_denied if denied_with(call("list_branches", {"repo": "web"}), "github.repo_not_allowed")

test_missing_repo_denied if denied_with(call("list_branches", {"owner": "acme"}), "github.repo_not_allowed")

test_non_string_owner_denied if denied_with(call("list_branches", {"owner": 1, "repo": "web"}), "github.repo_not_allowed")

test_empty_arguments_denied if denied_with(call("list_branches", {}), "github.repo_not_allowed")

test_issue_parent_in_other_repo_denied if {
	args := {"method": "create", "title": "t", "parent_issue_number": 1, "parent_owner": "evil", "parent_repo": "x"}
	denied_with(repo_call("issue_write", args), "github.repo_not_allowed")
}

# Either parent field alone counts as a parent reference, so it must name an allowed repository.
test_issue_parent_with_only_one_field_denied if {
	denied_with(repo_call("issue_write", {"method": "create", "title": "t", "parent_repo": "web"}), "github.repo_not_allowed")
	denied_with(repo_call("issue_write", {"method": "create", "title": "t", "parent_owner": "acme"}), "github.repo_not_allowed")
}

test_issue_parent_in_listed_repo_allowed if {
	args := {"method": "create", "title": "t", "parent_issue_number": 1, "parent_owner": "acme", "parent_repo": "web"}
	allowed(repo_call("issue_write", args))
}

test_issue_parent_with_only_owner_denied if {
	args := {"method": "create", "title": "t", "parent_owner": "acme"}
	denied_with(repo_call("issue_write", args), "github.repo_not_allowed")
}

# Protected branches.

branch_write_tools := ["push_files", "create_or_update_file", "delete_file"]

test_writes_to_protected_branch_denied if {
	files := {"files": [{"path": "a", "content": "x"}], "path": "a", "message": "m"}
	every tool in branch_write_tools {
		denied_with(repo_call(tool, object.union(files, {"branch": "main"})), "github.protected_branch")
	}
}

test_refs_heads_prefix_is_normalized if {
	request := repo_call("create_or_update_file", object.union(file_write, {"branch": "refs/heads/main"}))
	denied_with(request, "github.protected_branch")
}

test_heads_prefix_is_normalized if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"branch": "heads/main"})), "github.protected_branch")
}

test_branch_case_is_normalized if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"branch": "MAIN"})), "github.protected_branch")
}

test_branch_glob_matches if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"branch": "release/1.0"})), "github.protected_branch")
}

test_branch_glob_stops_at_separator if {
	allowed(repo_call("create_or_update_file", object.union(file_write, {"branch": "release/1.0/hotfix"})))
}

test_creating_a_protected_branch_name_denied if denied_with(repo_call("create_branch", {"branch": "main"}), "github.protected_branch")

test_default_protected_branches_apply_when_unconfigured if {
	cfg := {"allowed_repos": ["acme/web"]}
	request := repo_call("create_or_update_file", object.union(file_write, {"branch": "master"}))
	not github.allow with input as request with data.mcp_config.github as cfg
	"github.protected_branch" in codes(github.deny) with input as request with data.mcp_config.github as cfg
}

test_missing_branch_denied if {
	denied_with(repo_call("create_or_update_file", object.remove(file_write, ["branch"])), "github.invalid_branch")
}

test_non_string_branch_denied if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"branch": 1})), "github.invalid_branch")
}

invalid_branches := {"", " main", "main ", "ma in", "refs/tags/v1", "a..b", "/main", "main/", "a//b", "a~1", "a^", "a:b", "a?", "a*", "a[b", `a\b`, "@{-1}"}

test_invalid_branch_names_denied if {
	every branch in invalid_branches {
		denied_with(repo_call("create_or_update_file", object.union(file_write, {"branch": branch})), "github.invalid_branch")
	}
}

# Protected paths.

workflow_write := object.union(file_write, {"path": ".github/workflows/ci.yml"})

test_workflow_file_denied if denied_with(repo_call("create_or_update_file", workflow_write), "github.protected_path")

test_workflow_delete_denied if {
	denied_with(repo_call("delete_file", {"branch": "x", "message": "m", "path": ".github/workflows/ci.yml"}), "github.protected_path")
}

test_workflow_path_is_normalized if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"path": "./.github//workflows/ci.yml"})), "github.protected_path")
}

test_workflow_path_case_is_normalized if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"path": ".GitHub/Workflows/ci.yml"})), "github.protected_path")
}

test_one_workflow_file_in_a_push_denies_it if {
	files := [{"path": "a.txt", "content": "x"}, {"path": ".github/workflows/ci.yml", "content": "x"}]
	denied_with(repo_call("push_files", {"branch": "x", "message": "m", "files": files}), "github.protected_path")
}

test_composite_action_denied if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"path": ".github/actions/x/action.yml"})), "github.protected_path")
}

test_protected_paths_can_be_replaced_by_config if {
	cfg := object.union(config, {"protected_paths": ["infra/**"]})
	github.allow with input as repo_call("create_or_update_file", workflow_write) with data.mcp_config.github as cfg
	request := repo_call("create_or_update_file", object.union(file_write, {"path": "infra/main.tf"}))
	not github.allow with input as request with data.mcp_config.github as cfg
}

test_path_traversal_denied if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"path": "src/../.github/workflows/ci.yml"})), "github.invalid_path")
}

test_backslash_path_denied if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"path": `.github\workflows\ci.yml`})), "github.invalid_path")
}

test_missing_path_denied if {
	denied_with(repo_call("create_or_update_file", object.remove(file_write, ["path"])), "github.invalid_path")
}

test_push_entry_without_path_denied if {
	denied_with(repo_call("push_files", {"branch": "x", "message": "m", "files": [{"content": "x"}]}), "github.invalid_path")
}

test_push_without_files_denied if denied_with(repo_call("push_files", {"branch": "x", "message": "m"}), "github.invalid_path")

test_push_with_empty_files_denied if denied_with(repo_call("push_files", {"branch": "x", "message": "m", "files": []}), "github.invalid_path")

test_push_with_non_list_files_denied if denied_with(repo_call("push_files", {"branch": "x", "message": "m", "files": "a"}), "github.invalid_path")

test_symlink_write_denied if {
	denied_with(repo_call("create_or_update_file", object.union(file_write, {"allow_symlink_write": true})), "github.symlink_write")
}

test_symlink_write_false_allowed if allowed(repo_call("create_or_update_file", object.union(file_write, {"allow_symlink_write": false})))

# Destructive and administrative operations.

test_repository_deletion_denied if denied_with(repo_call("delete_repository", {}), "github.repo_deletion")

test_repository_deletion_cannot_be_enabled_by_config if {
	cfg := object.union(config, {"allow_repo_deletion": true, "allow_merge": true})
	not github.allow with input as repo_call("delete_repository", {}) with data.mcp_config.github as cfg
}

test_admin_tools_denied if {
	every tool in {"create_repository_ruleset", "custom_properties_write", "create_repository", "fork_repository"} {
		denied_with(repo_call(tool, {}), "github.admin_operation")
	}
}

test_unknown_tool_denied if denied_with(repo_call("force_push", {"branch": "main"}), "github.tool_not_supported")

test_unsupported_real_tool_denied if denied_with(call("create_gist", {"filename": "a", "content": "b"}), "github.tool_not_supported")

test_annotations_never_grant if {
	annotated := object.union(call("delete_repository", repo_args), {"tool": {"annotations": {"readOnlyHint": true, "destructiveHint": false}}})
	not allowed(annotated)
}

# Tools that are off unless configured.

gated_tools := {
	"merge_pull_request": ["allow_merge", "github.merge_not_allowed"],
	"update_pull_request_branch": ["allow_update_pr_branch", "github.update_pr_branch_not_allowed"],
	"actions_run_trigger": ["allow_workflow_runs", "github.workflow_run_not_allowed"],
	"assign_copilot_to_issue": ["allow_copilot", "github.copilot_not_allowed"],
	"assign_copilot_to_issue_with_intent": ["allow_copilot", "github.copilot_not_allowed"],
	"create_pull_request_with_copilot": ["allow_copilot", "github.copilot_not_allowed"],
	"request_copilot_review": ["allow_copilot", "github.copilot_not_allowed"],
	"get_secret_scanning_alert": ["allow_secret_alerts", "github.secret_alerts_not_allowed"],
	"list_secret_scanning_alerts": ["allow_secret_alerts", "github.secret_alerts_not_allowed"],
}

test_gated_tools_denied_by_default if {
	every tool, gate in gated_tools {
		denied_with(repo_call(tool, {}), gate[1])
	}
}

test_gated_tools_open_with_their_flag if {
	every tool, gate in gated_tools {
		cfg := object.union(config, {gate[0]: true})
		github.allow with input as repo_call(tool, {}) with data.mcp_config.github as cfg
	}
}

test_gate_needs_literal_true if {
	cfg := object.union(config, {"allow_merge": "true"})
	not github.allow with input as repo_call("merge_pull_request", {}) with data.mcp_config.github as cfg
}

test_gate_does_not_bypass_repo_allowlist if {
	cfg := object.union(config, {"allow_merge": true})
	request := call("merge_pull_request", {"owner": "evil", "repo": "x"})
	not github.allow with input as request with data.mcp_config.github as cfg
}

test_global_read_denied_by_default if denied_with(call("search_code", {"query": "repo:evil/x secret"}), "github.global_read_not_allowed")

test_global_read_opens_with_flag if {
	cfg := object.union(config, {"allow_global_read": true})
	github.allow with input as call("search_code", {"query": "x"}) with data.mcp_config.github as cfg
}

# Pull requests.

test_cross_repo_head_from_unknown_owner_denied if {
	denied_with(repo_call("create_pull_request", object.union(pr, {"head": "evil:feature"})), "github.cross_repo_head")
}

test_cross_repo_head_from_same_owner_allowed if allowed(repo_call("create_pull_request", object.union(pr, {"head": "acme:feature"})))

test_cross_repo_head_from_allowed_org_allowed if {
	allowed(repo_call("create_pull_request", object.union(pr, {"head": "Trusted-Org:feature"})))
}

# A pull request from a protected branch lets update_pull_request_branch merge its base
# into that branch: create_pull_request(head=main, base=evil), then update its branch.
test_pull_request_from_protected_branch_denied if {
	every head in ["main", "MAIN", "acme:main", "refs/heads/main", "release/1.0", "Trusted-Org:master"] {
		denied_with(repo_call("create_pull_request", object.union(pr, {"head": head, "base": "evil"})), "github.protected_branch")
	}
}

test_pull_request_from_unprotected_branch_into_protected_allowed if {
	allowed(repo_call("create_pull_request", object.union(pr, {"head": "acme:feature/main-fix"})))
}

test_pull_request_without_head_denied if denied_with(repo_call("create_pull_request", {"title": "t", "base": "main"}), "github.missing_argument")

test_pull_request_without_base_denied if denied_with(repo_call("create_pull_request", {"title": "t", "head": "x"}), "github.missing_argument")

test_pull_request_numeric_head_denied if denied_with(repo_call("create_pull_request", {"title": "t", "head": 1, "base": "main"}), "github.missing_argument")

review := {"pullNumber": 1, "method": "create"}

test_comment_review_allowed if allowed(repo_call("pull_request_review_write", object.union(review, {"event": "COMMENT"})))

test_review_with_no_event_allowed if allowed(repo_call("pull_request_review_write", review))

test_agent_approval_denied if {
	denied_with(repo_call("pull_request_review_write", object.union(review, {"event": "APPROVE"})), "github.pr_approval_not_allowed")
}

test_agent_approval_denied_in_any_case if {
	denied_with(repo_call("pull_request_review_write", object.union(review, {"event": "approve"})), "github.pr_approval_not_allowed")
}

test_non_string_review_event_denied if {
	denied_with(repo_call("pull_request_review_write", object.union(review, {"event": 1})), "github.pr_approval_not_allowed")
}

# Only the events the server lists, other than APPROVE, pass without allow_pr_approval.
test_review_event_is_an_allowlist if {
	every event in [" APPROVE", "APPROVE ", "approve\n", "DISMISS", ""] {
		denied_with(repo_call("pull_request_review_write", object.union(review, {"event": event})), "github.pr_approval_not_allowed")
	}
	allowed(repo_call("pull_request_review_write", object.union(review, {"event": "REQUEST_CHANGES"})))
}

test_agent_approval_opens_with_flag if {
	cfg := object.union(config, {"allow_pr_approval": true})
	request := repo_call("pull_request_review_write", object.union(review, {"event": "APPROVE"}))
	github.allow with input as request with data.mcp_config.github as cfg
}

test_resolving_a_thread_denied if {
	request := repo_call("pull_request_review_write", {"pullNumber": 1, "method": "resolve_thread", "threadId": "PRRT_1"})
	denied_with(request, "github.review_method_not_allowed")
}

test_review_without_method_denied if denied_with(repo_call("pull_request_review_write", {"pullNumber": 1}), "github.review_method_not_allowed")

# Approval and audit.

test_write_needs_approval_when_configured if {
	cfg := object.union(config, {"require_approval_for_writes": true})
	github.require_approval with input as repo_call("create_pull_request", pr) with data.mcp_config.github as cfg
}

test_read_does_not_need_approval if {
	cfg := object.union(config, {"require_approval_for_writes": true})
	not github.require_approval with input as repo_call("get_commit", {}) with data.mcp_config.github as cfg
}

test_listed_tool_needs_approval if {
	cfg := object.union(config, {"require_approval_tools": ["merge_pull_request"]})
	github.require_approval with input as repo_call("merge_pull_request", {}) with data.mcp_config.github as cfg
	not github.require_approval with input as repo_call("create_pull_request", pr) with data.mcp_config.github as cfg
}

test_audit_tags if {
	github.audit_tags == {"github:read"} with input as repo_call("get_commit", {})
	github.audit_tags == {"github:write"} with input as repo_call("create_pull_request", pr)
	github.audit_tags == {"github:write"} with input as repo_call("merge_pull_request", {})
	github.audit_tags == {"github:read"} with input as call("search_code", {"query": "x"})
}

test_missing_tool_name_denied if {
	not github.allow with input as {"arguments": repo_args} with data.mcp_config.github as config
	codes(github.deny) == {"github.tool_not_supported"} with input as {"arguments": repo_args}
		with data.mcp_config.github as config
}

test_repository_path_with_control_characters_denied if {
	every path in ["src/a\u0000.go", "src/a\n.go", "src/\u007f.go"] {
		denied_with(repo_call("create_or_update_file", object.union(file_write, {"path": path})), "github.invalid_path")
	}
}

# The server puts the path into the request URL as it is, so GitHub decodes "%67" to "g" and
# drops everything from "?" or "#". Each of these wrote a protected file while the pack saw
# another name.
paths_the_url_would_rewrite := [
	".%67ithub/workflows/ci.yml",
	".github/workflows%2Fci.yml",
	".github/%77orkflows/ci.yml",
	"%2egithub/workflows/ci.yml",
	".github/workflows/ci.yml?x=1",
	".github/workflows/ci.yml#x",
	"CODEOWNERS?x=1",
	"CODEOWNERS#x",
	"src/100%.go",
]

test_repository_path_with_url_syntax_denied if {
	every path in paths_the_url_would_rewrite {
		denied_with(repo_call("create_or_update_file", object.union(file_write, {"path": path})), "github.invalid_path")
		denied_with(repo_call("delete_file", {"branch": "x", "message": "m", "path": path}), "github.invalid_path")
		files := [{"path": "a.txt", "content": "x"}, {"path": path, "content": "x"}]
		denied_with(repo_call("push_files", {"branch": "x", "message": "m", "files": files}), "github.invalid_path")
	}
}

test_ordinary_repository_paths_still_allowed if {
	every path in ["src/a.go", "docs/My File (1).md", "a+b=c@2x.png", "pkg/[id]/~page.tsx", "données/é.txt"] {
		allowed(repo_call("create_or_update_file", object.union(file_write, {"path": path})))
	}
}

# Configuration types. A deny list given as a string used to switch its check off.

test_protected_branches_as_a_string_denies if {
	cfg := object.union(config, {"protected_branches": "main"})
	request := repo_call("push_files", {"branch": "main", "message": "m", "files": [{"path": "a.txt", "content": "x"}]})
	not github.allow with input as request with data.mcp_config.github as cfg
	"github.invalid_config" in codes(github.deny) with input as request with data.mcp_config.github as cfg
}

test_protected_paths_as_a_string_denies if {
	cfg := object.union(config, {"protected_paths": ".github/workflows/**"})
	request := repo_call("create_or_update_file", object.union(file_write, {"path": ".github/workflows/ci.yml"}))
	not github.allow with input as request with data.mcp_config.github as cfg
	"github.invalid_config" in codes(github.deny) with input as request with data.mcp_config.github as cfg
}

# An approval flag given as a string used to let writes through without approval.
test_approval_flag_as_a_string_denies if {
	cfg := object.union(config, {"require_approval_for_writes": "true"})
	request := repo_call("create_pull_request", pr)
	not github.allow with input as request with data.mcp_config.github as cfg
	"github.invalid_config" in codes(github.deny) with input as request with data.mcp_config.github as cfg
}

# Every documented key, each with a value of the wrong type.
wrongly_typed_config := {
	"allowed_repos": "acme/web",
	"allowed_orgs": "acme",
	"protected_branches": "main",
	"protected_paths": ".github/**",
	"require_approval_tools": "merge_pull_request",
	"allow_merge": "true",
	"allow_update_pr_branch": "true",
	"allow_workflow_runs": "true",
	"allow_copilot": "true",
	"allow_secret_alerts": "true",
	"allow_global_read": "true",
	"allow_pr_approval": "true",
	"require_approval_for_writes": "true",
}

test_every_config_key_is_type_checked if {
	request := repo_call("list_branches", {})
	every key, value in wrongly_typed_config {
		cfg := object.union(config, {key: value})
		not github.allow with input as request with data.mcp_config.github as cfg
		"github.invalid_config" in codes(github.deny) with input as request with data.mcp_config.github as cfg
	}
}

test_config_that_is_not_an_object_denies if {
	"github.invalid_config" in codes(github.deny) with input as repo_call("list_branches", {})
		with data.mcp_config.github as ["acme/web"]
}

test_valid_config_has_no_config_problem if {
	not "github.invalid_config" in codes(github.deny) with input as repo_call("list_branches", {})
		with data.mcp_config.github as config
}
