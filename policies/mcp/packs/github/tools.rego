# Which GitHub MCP server tools the pack knows, and how it treats each group.
package mcp.packs.github

# Read tools that take a required owner and repo. Secret scanning is gated below.
repo_read_tools := {
	"actions_get",
	"actions_list",
	"get_code_quality_finding",
	"get_code_scanning_alert",
	"get_commit",
	"get_dependabot_alert",
	"get_discussion",
	"get_discussion_comments",
	"get_file_contents",
	"get_job_logs",
	"get_label",
	"get_latest_release",
	"get_release_by_tag",
	"get_repository_tree",
	"get_tag",
	"issue_read",
	"list_branches",
	"list_code_scanning_alerts",
	"list_commits",
	"list_dependabot_alerts",
	"list_issues",
	"list_label",
	"list_pull_requests",
	"list_releases",
	"list_repository_collaborators",
	"list_repository_security_advisories",
	"list_tags",
	"pull_request_read",
}

repo_write_tools := {
	"add_comment_to_pending_review",
	"add_issue_comment",
	"add_reply_to_pull_request_comment",
	"create_branch",
	"create_or_update_file",
	"create_pull_request",
	"delete_file",
	"issue_write",
	"label_write",
	"pull_request_review_write",
	"push_files",
	"sub_issue_write",
	"update_issue_comment",
	"update_pull_request",
}

# Repo-scoped tools that stay off until a config flag turns them on.
gated_tools := {
	"merge_pull_request": {
		"flag": "allow_merge", "code": "merge_not_allowed", "write": true,
		"reason": "merges are off because the arguments do not reveal the target branch",
	},
	"update_pull_request_branch": {
		"flag": "allow_update_pr_branch", "code": "update_pr_branch_not_allowed", "write": true,
		"reason": "updating a pull request branch is off because the arguments do not reveal the head branch it writes to",
	},
	"actions_run_trigger": {
		"flag": "allow_workflow_runs", "code": "workflow_run_not_allowed", "write": true,
		"reason": "triggering workflows is off because they run code with repository secrets",
	},
	"assign_copilot_to_issue": {
		"flag": "allow_copilot", "code": "copilot_not_allowed", "write": true,
		"reason": "delegating work to Copilot is off",
	},
	"assign_copilot_to_issue_with_intent": {
		"flag": "allow_copilot", "code": "copilot_not_allowed", "write": true,
		"reason": "delegating work to Copilot is off",
	},
	"create_pull_request_with_copilot": {
		"flag": "allow_copilot", "code": "copilot_not_allowed", "write": true,
		"reason": "delegating work to Copilot is off",
	},
	"request_copilot_review": {
		"flag": "allow_copilot", "code": "copilot_not_allowed", "write": true,
		"reason": "delegating work to Copilot is off",
	},
	"get_secret_scanning_alert": {
		"flag": "allow_secret_alerts", "code": "secret_alerts_not_allowed", "write": false,
		"reason": "secret scanning alerts are off because they can reveal secrets",
	},
	"list_secret_scanning_alerts": {
		"flag": "allow_secret_alerts", "code": "secret_alerts_not_allowed", "write": false,
		"reason": "secret scanning alerts are off because they can reveal secrets",
	},
}

# These are not scoped to one repository, so the allowlist cannot constrain them.
global_read_tools := {
	"get_me",
	"search_code",
	"search_commits",
	"search_issues",
	"search_orgs",
	"search_pull_requests",
	"search_repositories",
	"search_users",
}

admin_tools := {
	"create_repository",
	"create_repository_ruleset",
	"custom_properties_write",
	"fork_repository",
}

branch_tools := {"create_branch", "create_or_update_file", "delete_file", "push_files"}

single_path_tools := {"create_or_update_file", "delete_file"}
