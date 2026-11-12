# Changelog

Each release's `policy_version` matches its tag. Every decision carries it, so you can tell which rules made a decision.

## 0.1.2

No policy rule changed in this release. Decisions are the same as in 0.1.1.

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
