# github pack

Limits calls to the GitHub MCP server to allowed repositories, keeps agents off protected branches and paths, and turns off operations that are destructive or hard to check. An agent can open a pull request into `main` but cannot push to it. Applies when `server.name` is `github`, or an alias for it.

Verified against: [`github/github-mcp-server`](https://github.com/github/github-mcp-server) v2.1.0, from `README.md` and `pkg/github/pullrequests.go` at that tag.

## Tool coverage

Only tools listed here can ever be allowed. A tool added in a later server release is denied until this pack is updated.

| Group | Tools | Default |
|---|---|---|
| Repository reads | `actions_get`, `actions_list`, `get_code_quality_finding`, `get_code_scanning_alert`, `get_commit`, `get_dependabot_alert`, `get_discussion`, `get_discussion_comments`, `get_file_contents`, `get_job_logs`, `get_label`, `get_latest_release`, `get_release_by_tag`, `get_repository_tree`, `get_tag`, `issue_read`, `list_branches`, `list_code_scanning_alerts`, `list_commits`, `list_dependabot_alerts`, `list_issues`, `list_label`, `list_pull_requests`, `list_releases`, `list_repository_collaborators`, `list_repository_security_advisories`, `list_tags`, `pull_request_read` | Allowed on allowed repositories |
| Repository writes | `add_comment_to_pending_review`, `add_issue_comment`, `add_reply_to_pull_request_comment`, `create_branch`, `create_or_update_file`, `create_pull_request`, `delete_file`, `issue_write`, `label_write`, `pull_request_review_write`, `push_files`, `sub_issue_write`, `update_issue_comment`, `update_pull_request` | Allowed on allowed repositories, subject to the checks below |
| Merging | `merge_pull_request` | Off, `allow_merge` |
| Updating a pull request branch | `update_pull_request_branch` | Off, `allow_update_pr_branch` |
| Workflow runs | `actions_run_trigger` | Off, `allow_workflow_runs` |
| Copilot | `assign_copilot_to_issue`, `assign_copilot_to_issue_with_intent`, `create_pull_request_with_copilot`, `request_copilot_review` | Off, `allow_copilot` |
| Secret alerts | `get_secret_scanning_alert`, `list_secret_scanning_alerts` | Off, `allow_secret_alerts` |
| Global reads | `get_me`, `search_code`, `search_commits`, `search_issues`, `search_orgs`, `search_pull_requests`, `search_repositories`, `search_users` | Off, `allow_global_read` |
| Administration | `create_repository`, `create_repository_ruleset`, `custom_properties_write`, `fork_repository` | Always denied |
| Deletion | `delete_repository` | Always denied |

Everything else, including gists, projects, notifications and stars, is denied as not supported.

## Deny codes

| Code | Denies when |
|---|---|
| `github.repo_not_allowed` | `owner`/`repo` is not allowed, or is missing or malformed, or an `issue_write` parent repository is not allowed |
| `github.repo_deletion` | the tool is `delete_repository` |
| `github.admin_operation` | the tool is in the administration group |
| `github.tool_not_supported` | the tool is not covered by this pack |
| `github.merge_not_allowed` | the tool is `merge_pull_request` and `allow_merge` is off |
| `github.update_pr_branch_not_allowed` | the tool is `update_pull_request_branch` and `allow_update_pr_branch` is off |
| `github.workflow_run_not_allowed` | the tool is `actions_run_trigger` and `allow_workflow_runs` is off |
| `github.copilot_not_allowed` | the tool is in the Copilot group and `allow_copilot` is off |
| `github.secret_alerts_not_allowed` | the tool is in the secret alerts group and `allow_secret_alerts` is off |
| `github.global_read_not_allowed` | the tool is in the global reads group and `allow_global_read` is off |
| `github.invalid_branch` | `branch` is missing or is not a plain branch name |
| `github.protected_branch` | a write or branch creation targets a protected branch, or a pull request's `head` is a protected branch |
| `github.invalid_path` | a file path is missing, malformed or has traversal |
| `github.protected_path` | a file path matches `protected_paths` |
| `github.symlink_write` | `create_or_update_file` sets `allow_symlink_write` |
| `github.missing_argument` | `create_pull_request` has no string `base` or `head` |
| `github.cross_repo_head` | a pull request `head` of the form `owner:branch` names an owner that is neither this repository's owner nor an allowed organization |
| `github.review_method_not_allowed` | `pull_request_review_write` uses a method other than `create`, `submit_pending` or `delete_pending` |
| `github.pr_approval_not_allowed` | a review's `event` is present and is not `COMMENT` or `REQUEST_CHANGES`, and `allow_pr_approval` is off |

## Configuration

Config lives under `data.mcp_config.github`. With no config, no repository is allowed.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `allowed_repos` | list of `owner/repo` | none | Allowed repositories. Case-insensitive. |
| `allowed_orgs` | list of owners | none | Owners whose every repository is allowed. Case-insensitive. |
| `protected_branches` | list of globs | `main`, `master` | Branches agents cannot write to or create. `*` stops at `/`, and `**` crosses it. |
| `protected_paths` | list of globs | `.github/workflows/**`, `.github/actions/**` | Repository paths agents cannot change. Setting this replaces the default. |
| `allow_merge` | boolean | `false` | Turn on `merge_pull_request` |
| `allow_update_pr_branch` | boolean | `false` | Turn on `update_pull_request_branch`. It merges a pull request's base into its head branch, which its arguments do not name, so it can write to a protected branch through a pull request a human opened from one. |
| `allow_workflow_runs` | boolean | `false` | Turn on `actions_run_trigger` |
| `allow_copilot` | boolean | `false` | Turn on the Copilot group |
| `allow_secret_alerts` | boolean | `false` | Turn on the secret alerts group |
| `allow_global_read` | boolean | `false` | Turn on the global reads group |
| `allow_pr_approval` | boolean | `false` | Let an agent approve a pull request |
| `require_approval_for_writes` | boolean | `false` | Hold every write for human approval |
| `require_approval_tools` | list of tool names | none | Hold these tools for human approval, for example `merge_pull_request` |

Only a literal `true` turns on a flag.

## Why these defaults

- **Merges are off because the target is invisible.** `merge_pull_request` takes only a pull request number, so the policy cannot tell whether it lands on a protected branch. The example config turns merging on but requires human approval.
- **Search is off because it escapes the allowlist.** `search_code` takes a free-text query, and `repo:other/private` inside it would reach outside the allowed repositories.
- **Workflow files are protected because they run with secrets.** An agent that can edit `.github/workflows/` on any branch can often run code with the repository's credentials.
- **Workflow runs and Copilot delegation act indirectly.** Both start work the policy cannot inspect.
- **`resolve_thread` is off because it ignores `owner` and `repo`.** It acts on a thread ID the allowlist cannot check.

## Limitations

- **The default branch is not visible.** The arguments do not say which branch is a repository's default, so protection comes from the `protected_branches` list. A repository whose default is `develop` needs that name added.
- **Use GitHub branch protection as well.** This pack is a layer in front of the server, not a replacement for rulesets, least-privilege tokens or required reviews.
- **Tools that act on a pull request number cannot see its branches.** `merge_pull_request` and `update_pull_request_branch` are off by default for this reason. An agent cannot open a pull request from a protected branch, which closes the path where `update_pull_request_branch` merges an agent's branch into `main`, but a pull request a human opened from one is still a target once these tools are on.
- **CI can run code from any branch.** `protected_paths` stops edits to workflow files, but a workflow that runs on `push` or `pull_request` may run scripts the agent can change, such as a `Makefile` or `package.json`, with the repository's secrets. Add those paths, and other CI systems' files such as `Jenkinsfile` or `.circleci/**`, to `protected_paths` if your workflows run them, and keep secrets out of workflows that run on branches.
- **Branch names are matched strictly.** Names with characters outside letters, digits and `. _ / # + = @ -` are refused, including non-ASCII names, even when git would accept them.
- **Resources are not covered.** This pack authorizes tool calls only. If your deployment exposes MCP resources from this server, the integration must authorize them separately.
