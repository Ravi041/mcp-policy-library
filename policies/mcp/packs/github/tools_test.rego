package mcp.packs.github_test

import data.mcp.packs.github

# Owner and repo names are validated before the allowlist, which matters most for an allowed
# organization, where any repo name under it would otherwise pass.
test_malformed_repo_names_denied_even_in_an_allowed_org if {
	every name in ["../../other", "x/y", "web repo", "", ".", "..", "a?b", "a#b"] {
		denied_with(call("list_branches", {"owner": "trusted-org", "repo": name}), "github.repo_not_allowed")
	}
	denied_with(call("list_branches", {"owner": "trusted-org/x", "repo": "web"}), "github.repo_not_allowed")
	denied_with(call("list_branches", {"owner": 1, "repo": "web"}), "github.repo_not_allowed")
	allowed(call("list_branches", {"owner": "trusted-org", "repo": "any.repo_name-1"}))
}

# Every supported tool, named here rather than read from the policy, so removing one from the
# policy fails a test. Checked against github-mcp-server v2.1.0.
supported_repo_reads := [
	"actions_get", "actions_list", "get_code_quality_finding", "get_code_scanning_alert",
	"get_commit", "get_dependabot_alert", "get_discussion", "get_discussion_comments",
	"get_file_contents", "get_job_logs", "get_label", "get_latest_release", "get_release_by_tag",
	"get_repository_tree", "get_tag", "issue_read", "list_branches", "list_code_scanning_alerts",
	"list_commits", "list_dependabot_alerts", "list_issues", "list_label", "list_pull_requests",
	"list_releases", "list_repository_collaborators", "list_repository_security_advisories",
	"list_tags", "pull_request_read",
]

supported_repo_writes := {
	"add_comment_to_pending_review": {},
	"add_issue_comment": {},
	"add_reply_to_pull_request_comment": {},
	"create_branch": {"branch": "feature/x"},
	"create_or_update_file": file_write,
	"create_pull_request": pr,
	"delete_file": {"branch": "feature/x", "path": "src/a.go", "message": "m"},
	"issue_write": {"method": "create", "title": "t"},
	"label_write": {},
	"pull_request_review_write": {"pullNumber": 1, "method": "create"},
	"push_files": {"branch": "feature/x", "message": "m", "files": [{"path": "a.txt", "content": "x"}]},
	"sub_issue_write": {},
	"update_issue_comment": {},
	"update_pull_request": {},
}

supported_global_reads := [
	"get_me", "search_code", "search_commits", "search_issues", "search_orgs",
	"search_pull_requests", "search_repositories", "search_users",
]

test_every_supported_read_allowed_on_a_listed_repo if {
	every tool in supported_repo_reads {
		allowed(repo_call(tool, {}))
		github.audit_tags == {"github:read"} with input as repo_call(tool, {}) with data.mcp_config.github as config
	}
}

test_every_supported_write_allowed_on_a_listed_repo if {
	every tool, arguments in supported_repo_writes {
		allowed(repo_call(tool, arguments))
		github.audit_tags == {"github:write"} with input as repo_call(tool, arguments) with data.mcp_config.github as config
	}
}

test_every_supported_global_read_allowed_with_its_flag if {
	cfg := object.union(config, {"allow_global_read": true})
	every tool in supported_global_reads {
		github.allow with input as call(tool, {}) with data.mcp_config.github as cfg
		github.audit_tags == {"github:read"} with input as call(tool, {}) with data.mcp_config.github as cfg
	}
}

test_every_supported_write_needs_approval_with_the_flag if {
	cfg := object.union(config, {"require_approval_for_writes": true})
	every tool, arguments in supported_repo_writes {
		github.require_approval with input as repo_call(tool, arguments) with data.mcp_config.github as cfg
	}
}
