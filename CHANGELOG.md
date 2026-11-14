# Changelog

Each release's `policy_version` matches its tag. Every decision carries it, so you can tell which rules made a decision.

## 0.1.4

The first release since 0.1.1. It also ships the changes listed under 0.1.3 and 0.1.2, so read those too when upgrading from 0.1.1.

### Security

- **postgres (medium):** With `denied_schemas` set, `pg_stat_activity` showed the values other sessions wrote to a denied schema. It keeps each connection's last statement with its literals, even after the connection goes idle. On PostgreSQL 17.11 through agentgateway, `SELECT * FROM secrets.api_keys` was refused, but `SELECT query FROM pg_stat_activity` returned `INSERT INTO secrets.api_keys VALUES ('billing', 'sk_live_...')` from another connection. PostgreSQL shows other roles' statements only to superusers and members of `pg_read_all_stats`, so this mattered when the agent shared a role with the application or held one of those. `pg_stat_activity`, the functions `pg_stat_get_activity` and `pg_stat_get_backend_activity` that return the same text, and `pg_stat_statements` are now refused when `denied_schemas` is set, with the new code `postgres.activity_not_allowed`.

### Fixed

- **tests:** The allowed-call check in `make e2e-docker` could not fail, because it was a single comparison under `opa eval --fail`. It now also checks `require_approval` and `deny`, like the other checks.
- **agentgateway walkthrough:** On a first run, the calls that reached Postgres failed with HTTP 400 while the gateway downloaded the `postgres-mcp` image. `try.sh up` now pulls it first. It also prints a note when it keeps a `data.json` that differs from the default that `check` expects.

## 0.1.3

Not published as a release. Its changes ship in 0.1.4.

### Security

Found in a penetration test of 0.1.2. Upgrade before relying on the GitHub or Postgres packs.

- **github (high):** A percent-encoded file path went around `protected_paths`. `create_or_update_file` with the path `.%67ithub/workflows/ci.yml` was allowed, because the pack compared the text as sent and refused only the escapes for `.`, `/` and `\`. `github-mcp-server` v2.1.0 puts the path into the request URL without escaping it, which was confirmed against a local mock of the API, so GitHub would decode it to `.github/workflows/ci.yml`. It was not tried against github.com. The pack now refuses any repository path that contains `%`.
- **github (medium):** A path ending in a query or fragment, such as `CODEOWNERS?x=1` or `CODEOWNERS#x`, did not match a protected path given by name, while the URL built from it still addresses `CODEOWNERS`. The pack now refuses any repository path that contains `?` or `#`. Both refusals use `github.invalid_path` and apply to `create_or_update_file`, `delete_file` and every file of `push_files`.
- **postgres (medium):** Extension functions that run SQL given as a string, name a table in a string or reach the network were not blocked, so a statement the pack classed as a read could write, read a denied schema or call out from the database host. Examples: `crosstab('SELECT ... FROM secrets.tokens')`, `DropGeometryTable('public', 'users')`, `http_get('http://169.254.169.254/...')`, `aws_s3.query_export_to_s3(...)` and `pg_background_launch('DROP TABLE users')`. The pack now blocks 36 more functions, 173 in all, from tablefunc, xml2, pageinspect, PostGIS, pgsql-http, pg_net, aws_s3, aws_lambda, pg_background and Citus. These were found by reading the policy and checked in each extension's install script or reference, not on a running database. The [pack README](packs/postgres/README.md#blocked-functions) lists them by extension.
- **postgres (low):** `pg_authid`, `pg_shadow`, `pg_user_mapping`, `pg_user_mappings`, `pg_subscription`, `pg_largeobject` and the `pg_toast` schema could be named in a read. They hold password hashes, connection passwords, large-object data and the stored values of other tables, including tables in a denied schema. PostgreSQL shows them only to privileged roles, so this mattered when the agent's role was one. They are now refused, with the new code `postgres.sensitive_catalog`.

### Changed

- **github:** A file path that contains `%`, `?` or `#` is refused for writes, including a real file such as `docs/C#/intro.md`. Reads are not affected.
- **postgres:** A function of your own named like a newly blocked one, such as `http`, `invoke` or `crosstab`, is now refused, and so is a column or alias named like one of the refused catalogs. Run `make replay` on a recorded decision log to see which of your calls move before you upgrade.

## 0.1.2

Not published as a release. Its changes ship in 0.1.3.

No policy rule changed in this version. Decisions are the same as in 0.1.1.

### Added

- **Trace replay.** `make replay TRACE=<decision log> CONFIG=<config>` evaluates recorded tool calls again and fails when any outcome moved: a call that was refused and is now allowed, or a call that was allowed and is now refused. It also fails when an allowed call's input breaks the input schema. Reviewed moves can be accepted by decision ID. See [docs/testing.md](docs/testing.md#replaying-real-traces).

### Fixed

- **tests:** Four checks could not fail, because `opa eval --fail` exits 0 for a comparison that is false: the comparison of each example with its `decision.json` in `make fixtures` and `make e2e`, and the `mcp_config`-only and `policy_version` gates in `make qa`. They now use unification. Every example and gate passes with the corrected checks.

## 0.1.1

### Security

Found in a penetration test of v0.1.0 and a security review of the fixes that followed. Upgrade before relying on the Postgres or GitHub packs. Advisory: [GHSA-2g75-x7cr-hv92](https://github.com/Ravi041/mcp-policy-library/security/advisories/GHSA-2g75-x7cr-hv92).

- **postgres (high):** Functions that run SQL given as a string, or that change the server, were missing from the blocked list, so a statement the pack classed as a read could write. On PostgreSQL 17, `SELECT dblink_connect_u(...), dblink_send_query('c', 'DELETE FROM accounts')` deleted every row, `cron.schedule('* * * * *', 'DROP TABLE users')` dropped the table a minute later, and `dblink_build_sql_insert('secrets.tokens', ...)` returned a row from a denied schema. The pack now blocks 40 more functions, 137 in all: every `dblink` function, pg_cron's scheduling functions, adminpack's file functions, `pg_start_backup` and `pg_stop_backup` from PostgreSQL 14, the statistics writers from PostgreSQL 18, and four more `pg_ls_*` directory listings.
- **postgres (medium):** A `--` comment between a quoted schema name and its dot, as in `"hr-data" -- x` and then `.salaries` on the next line, hid the reference from `denied_schemas`. PostgreSQL treats the comment as whitespace and returned the rows. Quoted names are now matched after comments are removed.
- **all packs (medium):** A config value of the wrong type switched deny lists off without any error. With `"protected_branches": "main"` instead of `["main"]`, a push to `main` was allowed; the same held for `protected_paths`, `denied_schemas` and `deny_globs`, and `"require_approval_for_writes": "true"` let writes through without approval. Every documented key is now type-checked, and a pack with a malformed config refuses every call with `<pack>.invalid_config`. The router does the same for `server_aliases`, with `main.invalid_config`.
- **postgres (low):** `EXPLAIN ("analyze")`, with the option name quoted, runs the statement but was not refused as `postgres.explain_analyze`. Writes inside it were already refused.
- **postgres (critical):** A dollar-quote tag with a non-ASCII letter, such as `$é$`, hid any SQL from the pack: writes, extra statements, blocked functions and denied schemas. Through agentgateway and `postgres-mcp`, it deleted every row of a table. The pack now refuses any `$` outside strings, comments and quoted identifiers, except positional parameters such as `$1`.
- **postgres (high):** A vertical tab between a name and `(` or `.` hid blocked function calls and denied schema references, because PostgreSQL treats it as whitespace and the pack did not. The pack now refuses control characters other than tab, newline and carriage return.
- **github (high):** An agent could merge any branch into a protected branch: open a pull request with `head: main` and `base` set to its own branch, then call `update_pull_request_branch`. Pull requests from protected branches are now refused, and `update_pull_request_branch` is off unless `allow_update_pr_branch` is set.
- **postgres (medium):** With `denied_schemas` set, `pg_stats` and the other planner statistics views returned sample values from denied schemas. They are now refused, as `postgres.statistics_not_allowed`.
- **postgres (low):** Denied schema names that need quoting, such as `my-secrets`, or that contain non-ASCII letters were not matched.
- **github (low):** A review's `event` is now checked against an allowlist, `COMMENT` and `REQUEST_CHANGES`, not against `APPROVE` alone.
- **agentgateway walkthrough:** The filesystem server now starts with the same directory as the policy's `read_paths`, so a symlink cannot lead it elsewhere, and the gateway's stats and readiness ports listen on localhost only. The README explains why agents must not share a host with the gateway: its admin endpoint serves backend credentials.
- **postgres:** `denied_schemas` could be bypassed by functions that take a table, schema or query as a string. `table_to_xml('secrets.tokens', ...)`, `schema_to_xml`, `database_to_xml`, their `_and_xmlschema` forms, `ts_rewrite` and `pg_logical_slot_peek_changes` returned rows from a denied schema on PostgreSQL 17.11. They are now blocked functions.
- **postgres:** Blocked functions with side effects that the list missed: `pg_notify`, advisory locks, large-object writes (`lo_creat`, `lowrite`, `lo_truncate`), BRIN and GIN index maintenance, statistics resets, WAL messages, replication slots and origins, and server control such as `pg_promote`. See the [full list](packs/postgres/README.md#blocked-functions).

### Added

- agentgateway adapter and a [runbook](docs/try-it-with-gateways.md) for trying the library behind a real MCP gateway.
- A status section in the README.
- Release bundles carry a GitHub build provenance attestation.

### Fixed

- `make test` and the other targets failed with GNU Make 3.81, the macOS default, because it did not find `opa` and `regal` in `.bin/`.
- The agentgateway walkthrough's forged-token check failed about one run in four, because it edited a base64url character that carries no signature data.

## 0.1.0

First release: the `baseline`, `filesystem`, `github` and `postgres` packs, the input and decision schemas, the OPA sidecar and Docker Compose integrations, and examples.
