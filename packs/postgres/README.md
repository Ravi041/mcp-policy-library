# postgres pack

Keeps calls to Postgres MCP servers read-only by default, and blocks DDL and destructive statements. Applies when `server.name` is `postgres`, or an alias for it.

Verified against:

- [`crystaldba/postgres-mcp`](https://github.com/crystaldba/postgres-mcp) v0.3.0, from `src/postgres_mcp/server.py` at that tag. Its latest release is from May 2025.
- `@modelcontextprotocol/server-postgres` 0.6.2, from [`modelcontextprotocol/servers-archived`](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/postgres). This server is archived, and npm marks it "Archived and unmaintained; no security guarantees". It is covered because it may still be deployed. Do not choose it for new work.

## Read this first: SQL inspection here is best-effort

**This pack is not a substitute for database permissions.** Rego has no SQL parser, so this pack scans the text of a statement. It catches common and known-evasive forms, and refuses syntax it cannot read reliably, but it will never catch everything. For example, `SELECT my_function()` is allowed when `my_function` writes data, because the policy cannot see what a function does.

Connect the server with a database role that has only the privileges you intend. Treat this pack as a second layer that gives clearer denials and blocks the obvious mistakes.

## How a statement is judged

1. **Scan.** Strings, comments and quoted identifiers are recognized left to right, so `'--'` is a string and not a comment.
2. **Refuse what cannot be read.** Backslashes, dollar quoting, `U&` escapes, block comments, NUL bytes and unterminated quotes are denied. PostgreSQL reads these differently than a simple scanner, so each could hide a statement. For example, in `SELECT E'\'' ; DROP TABLE users; --'`, the `DROP` runs in PostgreSQL but looks like part of a string to a naive scanner.
3. **Refuse multiple statements.** A trailing semicolon is fine. This also stops `COMMIT; DROP TABLE users`, which from reading the archived server's source looks able to escape its read-only transaction, since it passes the SQL straight to the driver. That escape has not been run against a live server here.
4. **Classify.** The statement's first keyword and the keywords in it decide its class.

| Class | Examples | Default | Flag |
|---|---|---|---|
| read | `SELECT`, `SHOW`, `VALUES`, `TABLE`, `EXPLAIN`, `WITH` | Allowed | none |
| write | `INSERT`, `UPDATE`, `DELETE`, `MERGE`, or a read form containing one, such as `WITH d AS (DELETE ...) SELECT` or `SELECT ... FOR UPDATE` | Denied | `allow_writes` |
| ddl | `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `GRANT`, `REVOKE`, `COMMENT`, `REINDEX`, `CLUSTER`, `VACUUM`, `ANALYZE`, `REFRESH`, `SECURITY`, `SELECT ... INTO`, or a read form containing a DDL keyword | Denied | `allow_ddl` |
| other | everything else: `COPY`, `BEGIN`, `COMMIT`, `SET`, `LOCK`, `DO`, `CALL`, `PREPARE`, `EXECUTE`, `LISTEN`, `NOTIFY`, `LOAD`, or a statement starting with `(` | Always denied | none |

The scan errs toward refusing. A column literally named `update` or `drop` makes a harmless `SELECT` look like a write. Quote the identifier, as in `SELECT "update" FROM t`, and it reads correctly.

## Tools

| Tool | Server | Default |
|---|---|---|
| `execute_sql` | postgres-mcp | Judged as above |
| `explain_query` | postgres-mcp | Judged as above; `analyze` must be absent or `false` |
| `query` | archived | Judged as above |
| `list_schemas`, `list_objects`, `get_object_details` | postgres-mcp | Allowed, subject to `denied_schemas` |
| `get_top_queries`, `analyze_db_health`, `analyze_workload_indexes` | postgres-mcp | Off unless in `allowed_optional_tools` |

Any other tool is denied. That includes `analyze_query_indexes`, because it takes a list of SQL strings this pack does not inspect.

## Deny codes

| Code | Denies when |
|---|---|
| `postgres.tool_not_supported` | the tool is not in the table above |
| `postgres.optional_tool_not_allowed` | an optional tool is not in `allowed_optional_tools` |
| `postgres.missing_argument` | `sql` is missing, blank or not a string, or `schema_name` is missing or not a string |
| `postgres.unparseable_sql` | the SQL uses syntax the pack refuses to interpret |
| `postgres.multiple_statements` | the SQL has more than one statement |
| `postgres.write_not_allowed` | the statement changes data and `allow_writes` is off |
| `postgres.ddl_not_allowed` | the statement changes schema or permissions and `allow_ddl` is off |
| `postgres.statement_not_allowed` | the statement is in the "other" class |
| `postgres.unbounded_write` | an `UPDATE` or `DELETE` has no `WHERE` and `allow_unbounded_writes` is off |
| `postgres.explain_analyze` | `EXPLAIN ANALYZE` appears, or `explain_query` sets `analyze`, because both run the statement |
| `postgres.blocked_function` | the SQL calls a blocked function |
| `postgres.denied_schema` | the SQL or `schema_name` references a denied schema |

## Blocked functions

These functions are denied in every statement, because they have side effects, reach the host or run SQL hidden in a string:

`cursor_to_xml`, `dblink`, `dblink_connect`, `dblink_exec`, `lo_create`, `lo_export`, `lo_from_bytea`, `lo_import`, `lo_put`, `lo_unlink`, `nextval`, `pg_cancel_backend`, `pg_create_restore_point`, `pg_ls_archive_statusdir`, `pg_ls_dir`, `pg_ls_logdir`, `pg_ls_tmpdir`, `pg_ls_waldir`, `pg_read_binary_file`, `pg_read_file`, `pg_reload_conf`, `pg_rotate_logfile`, `pg_sleep`, `pg_sleep_for`, `pg_sleep_until`, `pg_stat_file`, `pg_switch_wal`, `pg_terminate_backend`, `query_to_xml`, `query_to_xml_and_xmlschema`, `query_to_xmlschema`, `set_config`, `setval`, `ts_stat`.

This list is not exhaustive. Add your own with `extra_blocked_functions`, and rely on database privileges for anything that matters.

## Configuration

Config lives under `data.mcp_config.postgres`. With no config, read statements and metadata tools are allowed and everything else is denied.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `allow_writes` | boolean | `false` | Allow statements that change data |
| `allow_ddl` | boolean | `false` | Allow statements that change schema or permissions |
| `allow_unbounded_writes` | boolean | `false` | Allow `UPDATE` and `DELETE` without `WHERE` |
| `require_approval_for_writes` | boolean | `false` | Hold writes and DDL for human approval |
| `denied_schemas` | list of strings | none | Schemas that may not be referenced. Case-insensitive. |
| `extra_blocked_functions` | list of strings | none | Functions to block, on top of the list above. Case-insensitive. |
| `allowed_optional_tools` | list of tool names | none | Optional tools to turn on |

`allow_writes` does not imply `allow_ddl`, and neither allows the "other" class.

## Limitations

- **Function bodies are invisible.** A user-defined function can do anything its owner can.
- **`denied_schemas` is a text match on qualified names.** An unqualified name found through `search_path` is not caught, and a table alias equal to a denied schema name is refused.
- **Resources are not covered.** The archived server exposes table schemas as MCP resources, and this pack authorizes tool calls only.
