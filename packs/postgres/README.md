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
2. **Refuse what cannot be read.** Backslashes, dollar quoting (any `$` outside a string, except a positional parameter such as `$1`), `U&` escapes, block comments, control characters other than tab, newline and carriage return, and unterminated quotes are denied. PostgreSQL reads these differently than a simple scanner, so each could hide a statement. For example, in `SELECT E'\'' ; DROP TABLE users; --'`, the `DROP` runs in PostgreSQL but looks like part of a string to a naive scanner.
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
| `postgres.statistics_not_allowed` | `denied_schemas` is set and the SQL reads a planner statistics view or table: `pg_stats`, `pg_stats_ext`, `pg_stats_ext_exprs`, `pg_statistic` or `pg_statistic_ext_data`. These hold sample values from every table the role can read. |

## Blocked functions

These functions are denied in every statement, because they have side effects, reach the host, run SQL hidden in a string, or read a table or schema named in a string, which `denied_schemas` cannot see. Every name was checked in `pg_proc` on PostgreSQL 17.11 (`pg_stat_statements_reset` with that extension installed):

`brin_desummarize_range`, `brin_summarize_new_values`, `brin_summarize_range`, `cursor_to_xml`, `cursor_to_xmlschema`, `database_to_xml`, `database_to_xml_and_xmlschema`, `database_to_xmlschema`, `dblink`, `dblink_connect`, `dblink_exec`, `gin_clean_pending_list`, `lo_creat`, `lo_create`, `lo_export`, `lo_from_bytea`, `lo_import`, `lo_put`, `lo_truncate`, `lo_truncate64`, `lo_unlink`, `lowrite`, `nextval`, `pg_advisory_lock`, `pg_advisory_lock_shared`, `pg_advisory_xact_lock`, `pg_advisory_xact_lock_shared`, `pg_backup_start`, `pg_backup_stop`, `pg_cancel_backend`, `pg_copy_logical_replication_slot`, `pg_copy_physical_replication_slot`, `pg_create_logical_replication_slot`, `pg_create_physical_replication_slot`, `pg_create_restore_point`, `pg_drop_replication_slot`, `pg_import_system_collations`, `pg_log_backend_memory_contexts`, `pg_log_standby_snapshot`, `pg_logical_emit_message`, `pg_logical_slot_get_binary_changes`, `pg_logical_slot_get_changes`, `pg_logical_slot_peek_binary_changes`, `pg_logical_slot_peek_changes`, `pg_ls_archive_statusdir`, `pg_ls_dir`, `pg_ls_logdir`, `pg_ls_tmpdir`, `pg_ls_waldir`, `pg_notify`, `pg_promote`, `pg_read_binary_file`, `pg_read_file`, `pg_reload_conf`, `pg_replication_origin_advance`, `pg_replication_origin_create`, `pg_replication_origin_drop`, `pg_replication_origin_session_reset`, `pg_replication_origin_session_setup`, `pg_replication_origin_xact_reset`, `pg_replication_origin_xact_setup`, `pg_replication_slot_advance`, `pg_rotate_logfile`, `pg_sleep`, `pg_sleep_for`, `pg_sleep_until`, `pg_stat_file`, `pg_stat_reset`, `pg_stat_reset_replication_slot`, `pg_stat_reset_shared`, `pg_stat_reset_single_function_counters`, `pg_stat_reset_single_table_counters`, `pg_stat_reset_slru`, `pg_stat_reset_subscription_stats`, `pg_stat_statements_reset`, `pg_switch_wal`, `pg_sync_replication_slots`, `pg_terminate_backend`, `pg_try_advisory_lock`, `pg_try_advisory_lock_shared`, `pg_try_advisory_xact_lock`, `pg_try_advisory_xact_lock_shared`, `pg_wal_replay_pause`, `pg_wal_replay_resume`, `query_to_xml`, `query_to_xml_and_xmlschema`, `query_to_xmlschema`, `schema_to_xml`, `schema_to_xml_and_xmlschema`, `schema_to_xmlschema`, `set_config`, `setval`, `table_to_xml`, `table_to_xml_and_xmlschema`, `table_to_xmlschema`, `ts_rewrite`, `ts_stat`.

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
- **`denied_schemas` is a text match on qualified names.** An unqualified name found through `search_path` is not caught, and a table alias equal to a denied schema name is refused. Functions that take a table or query as a string, such as `table_to_xml('secrets.tokens', ...)`, can read any table the role can; the built-in ones are blocked, but an extension can add more. Catalog views such as `information_schema.columns` still show the names and types of a denied schema's columns, though not its rows. Revoke access to sensitive schemas in the database as well.
- **Resources are not covered.** The archived server exposes table schemas as MCP resources, and this pack authorizes tool calls only.
