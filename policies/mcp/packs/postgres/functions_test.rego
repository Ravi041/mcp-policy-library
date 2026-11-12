package mcp.packs.postgres_test

# Functions with side effects, or that run SQL hidden in a string.

blocked_function_calls := {
	"SELECT pg_read_file('/etc/passwd')",
	"SELECT PG_READ_FILE('/etc/passwd')",
	"SELECT pg_read_file ('/etc/passwd')",
	"SELECT pg_read_file\n('/etc/passwd')",
	"SELECT pg_catalog.pg_read_file('/etc/passwd')",
	"SELECT \"pg_read_file\"('/etc/passwd')",
	"SELECT \"pg_catalog\".\"pg_read_file\"('/etc/passwd')",
	"SELECT pg_sleep(100)",
	"SELECT pg_terminate_backend(1)",
	"SELECT set_config('role', 'admin', false)",
	"SELECT query_to_xml('DROP TABLE users', true, true, '')",
	"SELECT * FROM ts_stat('DROP TABLE users')",
	"SELECT lo_import('/etc/passwd')",
	"SELECT dblink_exec('x', 'DROP TABLE users')",
	"SELECT setval('s', 1)",
	"SELECT nextval('s')",
}

test_blocked_functions_denied if {
	every sql in blocked_function_calls {
		sql_denied_with(sql, "postgres.blocked_function")
	}
}

# These take a schema, table or query as a string, so `denied_schemas` cannot see what they
# read. Each was shown to return rows from a denied schema on PostgreSQL 17.11.
reads_through_a_name_in_a_string := {
	"SELECT table_to_xml('secrets.tokens', true, false, '')",
	"SELECT table_to_xml_and_xmlschema('secrets.tokens', true, false, '')",
	"SELECT schema_to_xml('secrets', true, false, '')",
	"SELECT schema_to_xml_and_xmlschema('secrets', true, false, '')",
	"SELECT database_to_xml(true, false, '')",
	"SELECT database_to_xml_and_xmlschema(true, false, '')",
	"SELECT ts_rewrite('a'::tsquery, 'SELECT t, t FROM secrets.tokens')",
	"SELECT * FROM pg_logical_slot_peek_changes('slot', NULL, NULL)",
	"SELECT * FROM pg_logical_slot_peek_binary_changes('slot', NULL, NULL)",
}

test_reads_through_a_name_in_a_string_denied if {
	every sql in reads_through_a_name_in_a_string {
		sql_denied_with(sql, "postgres.blocked_function")
	}
}

# Functions that change data, server state or other sessions. Every name was checked in
# pg_proc on PostgreSQL 17.11 (pg_stat_statements_reset with that extension installed).
side_effect_functions := {
	# Messages to other sessions, and locks that outlive the call.
	"pg_notify",
	"pg_advisory_lock",
	"pg_advisory_lock_shared",
	"pg_try_advisory_lock",
	"pg_try_advisory_lock_shared",
	"pg_advisory_xact_lock",
	"pg_advisory_xact_lock_shared",
	"pg_try_advisory_xact_lock",
	"pg_try_advisory_xact_lock_shared",
	# Large-object writes.
	"lo_creat",
	"lowrite",
	"lo_truncate",
	"lo_truncate64",
	# Index maintenance.
	"brin_summarize_new_values",
	"brin_summarize_range",
	"brin_desummarize_range",
	"gin_clean_pending_list",
	# Statistics resets.
	"pg_stat_reset",
	"pg_stat_reset_shared",
	"pg_stat_reset_single_table_counters",
	"pg_stat_reset_single_function_counters",
	"pg_stat_reset_slru",
	"pg_stat_reset_replication_slot",
	"pg_stat_reset_subscription_stats",
	"pg_stat_statements_reset",
	# WAL records, replication slots and origins.
	"pg_logical_emit_message",
	"pg_log_standby_snapshot",
	"pg_create_physical_replication_slot",
	"pg_create_logical_replication_slot",
	"pg_drop_replication_slot",
	"pg_copy_physical_replication_slot",
	"pg_copy_logical_replication_slot",
	"pg_replication_slot_advance",
	"pg_logical_slot_get_changes",
	"pg_logical_slot_get_binary_changes",
	"pg_sync_replication_slots",
	"pg_replication_origin_create",
	"pg_replication_origin_drop",
	"pg_replication_origin_advance",
	"pg_replication_origin_session_setup",
	"pg_replication_origin_session_reset",
	"pg_replication_origin_xact_setup",
	"pg_replication_origin_xact_reset",
	# Server control.
	"pg_backup_start",
	"pg_backup_stop",
	"pg_promote",
	"pg_wal_replay_pause",
	"pg_wal_replay_resume",
	"pg_import_system_collations",
	"pg_log_backend_memory_contexts",
	# Structure of tables in a denied schema, named in a string.
	"table_to_xmlschema",
	"schema_to_xmlschema",
	"database_to_xmlschema",
	"cursor_to_xmlschema",
}

test_side_effect_functions_denied if {
	every name in side_effect_functions {
		sql_denied_with(sprintf("SELECT %s(1)", [name]), "postgres.blocked_function")
	}
}

test_notify_and_advisory_lock_calls_denied if {
	sql_denied_with("SELECT pg_notify('orders', 'refund 42')", "postgres.blocked_function")
	sql_denied_with("SELECT pg_catalog.PG_ADVISORY_LOCK(1)", "postgres.blocked_function")
}

test_function_name_inside_a_string_is_only_text if allowed(sql_call("SELECT 'pg_sleep(1)'"))

test_column_with_blocked_name_is_not_a_call if allowed(sql_call("SELECT pg_sleep FROM t"))

test_extra_blocked_function if {
	cfg := {"extra_blocked_functions": ["My_Func"]}
	not allowed_with(sql_call("SELECT my_func(1)"), cfg)
	allowed_with(sql_call("SELECT other_func(1)"), cfg)
}

# The full list, named here rather than read from the policy, so removing a name fails a test.
all_blocked_functions := [
	"addgeometrycolumn",
	"alter_job",
	"brin_desummarize_range",
	"brin_summarize_new_values",
	"brin_summarize_range",
	"connectby",
	"crosstab",
	"crosstab2",
	"crosstab3",
	"crosstab4",
	"cursor_to_xml",
	"cursor_to_xmlschema",
	"database_to_xml",
	"database_to_xml_and_xmlschema",
	"database_to_xmlschema",
	"dblink",
	"dblink_build_sql_delete",
	"dblink_build_sql_insert",
	"dblink_build_sql_update",
	"dblink_cancel_query",
	"dblink_close",
	"dblink_connect",
	"dblink_connect_u",
	"dblink_current_query",
	"dblink_disconnect",
	"dblink_error_message",
	"dblink_exec",
	"dblink_fdw_validator",
	"dblink_fetch",
	"dblink_get_connections",
	"dblink_get_notify",
	"dblink_get_pkey",
	"dblink_get_result",
	"dblink_is_busy",
	"dblink_open",
	"dblink_send_query",
	"dropgeometrycolumn",
	"dropgeometrytable",
	"get_raw_page",
	"gin_clean_pending_list",
	"http",
	"http_delete",
	"http_get",
	"http_head",
	"http_patch",
	"http_post",
	"http_put",
	"http_reset_curlopt",
	"http_set_curlopt",
	"invoke",
	"lo_creat",
	"lo_create",
	"lo_export",
	"lo_from_bytea",
	"lo_import",
	"lo_put",
	"lo_truncate",
	"lo_truncate64",
	"lo_unlink",
	"lowrite",
	"master_run_on_worker",
	"nextval",
	"pg_advisory_lock",
	"pg_advisory_lock_shared",
	"pg_advisory_xact_lock",
	"pg_advisory_xact_lock_shared",
	"pg_background_detach",
	"pg_background_launch",
	"pg_background_result",
	"pg_backup_start",
	"pg_backup_stop",
	"pg_cancel_backend",
	"pg_clear_attribute_stats",
	"pg_clear_relation_stats",
	"pg_copy_logical_replication_slot",
	"pg_copy_physical_replication_slot",
	"pg_create_logical_replication_slot",
	"pg_create_physical_replication_slot",
	"pg_create_restore_point",
	"pg_drop_replication_slot",
	"pg_file_rename",
	"pg_file_sync",
	"pg_file_unlink",
	"pg_file_write",
	"pg_import_system_collations",
	"pg_log_backend_memory_contexts",
	"pg_log_standby_snapshot",
	"pg_logdir_ls",
	"pg_logical_emit_message",
	"pg_logical_slot_get_binary_changes",
	"pg_logical_slot_get_changes",
	"pg_logical_slot_peek_binary_changes",
	"pg_logical_slot_peek_changes",
	"pg_ls_archive_statusdir",
	"pg_ls_dir",
	"pg_ls_logdir",
	"pg_ls_logicalmapdir",
	"pg_ls_logicalsnapdir",
	"pg_ls_replslotdir",
	"pg_ls_summariesdir",
	"pg_ls_tmpdir",
	"pg_ls_waldir",
	"pg_notify",
	"pg_promote",
	"pg_read_binary_file",
	"pg_read_file",
	"pg_read_file_old",
	"pg_reload_conf",
	"pg_replication_origin_advance",
	"pg_replication_origin_create",
	"pg_replication_origin_drop",
	"pg_replication_origin_session_reset",
	"pg_replication_origin_session_setup",
	"pg_replication_origin_xact_reset",
	"pg_replication_origin_xact_setup",
	"pg_replication_slot_advance",
	"pg_restore_attribute_stats",
	"pg_restore_relation_stats",
	"pg_rotate_logfile",
	"pg_rotate_logfile_old",
	"pg_sleep",
	"pg_sleep_for",
	"pg_sleep_until",
	"pg_start_backup",
	"pg_stat_file",
	"pg_stat_reset",
	"pg_stat_reset_backend_stats",
	"pg_stat_reset_replication_slot",
	"pg_stat_reset_shared",
	"pg_stat_reset_single_function_counters",
	"pg_stat_reset_single_table_counters",
	"pg_stat_reset_slru",
	"pg_stat_reset_subscription_stats",
	"pg_stat_statements_reset",
	"pg_stop_backup",
	"pg_switch_wal",
	"pg_sync_replication_slots",
	"pg_terminate_backend",
	"pg_try_advisory_lock",
	"pg_try_advisory_lock_shared",
	"pg_try_advisory_xact_lock",
	"pg_try_advisory_xact_lock_shared",
	"pg_wal_replay_pause",
	"pg_wal_replay_resume",
	"populate_geometry_columns",
	"query_export_to_s3",
	"query_to_xml",
	"query_to_xml_and_xmlschema",
	"query_to_xmlschema",
	"run_command_on_all_nodes",
	"run_command_on_colocated_placements",
	"run_command_on_placements",
	"run_command_on_shards",
	"run_command_on_workers",
	"schedule",
	"schedule_in_database",
	"schema_to_xml",
	"schema_to_xml_and_xmlschema",
	"schema_to_xmlschema",
	"set_config",
	"setval",
	"st_estimatedextent",
	"st_findextent",
	"st_fromflatgeobuftotable",
	"table_import_from_s3",
	"table_to_xml",
	"table_to_xml_and_xmlschema",
	"table_to_xmlschema",
	"ts_rewrite",
	"ts_stat",
	"unschedule",
	"updategeometrysrid",
	"xpath_table",
]

test_every_blocked_function_denied if {
	count(all_blocked_functions) == 173
	every name in all_blocked_functions {
		sql_denied_with(sprintf("SELECT %s(1)", [name]), "postgres.blocked_function")
	}
}

# Found in the 0.1.1 security review. Each was checked in pg_proc; the version column of the
# README says where. The calls below are the ones shown to work on a live server.
hidden_sql_calls := {
	# dblink_connect_u and dblink_send_query deleted every row of a table on PostgreSQL 17.11.
	"SELECT dblink_connect_u('c', 'dbname=demo'), dblink_send_query('c', 'DELETE FROM accounts')",
	"SELECT dblink_open('c', 'cur', 'SELECT * FROM secrets.tokens')",
	"SELECT * FROM dblink_fetch('c', 'cur', 10) AS t(token text)",
	# Returned the row's values, ghp_ token included, from a denied schema.
	"SELECT dblink_build_sql_insert('secrets.tokens', '1', 1, '{1}', '{1}')",
	# pg_cron 1.6 ran this DROP TABLE within a minute.
	"SELECT cron.schedule('* * * * *', 'DROP TABLE users')",
	"SELECT cron.schedule_in_database('j', '* * * * *', 'DELETE FROM users', 'demo')",
	"SELECT cron.alter_job(1, command := 'DROP TABLE users')",
	"SELECT cron.unschedule(1)",
	# adminpack (PostgreSQL 16 and earlier) writes files on the database host.
	"SELECT pg_file_write('/tmp/x', 'data', false)",
	"SELECT pg_catalog.pg_file_unlink('/var/lib/postgresql/data/postgresql.conf')",
}

test_hidden_sql_calls_denied if {
	every sql in hidden_sql_calls {
		sql_denied_with(sql, "postgres.blocked_function")
	}
}

added_in_security_review := {
	# Every dblink function: connections, hidden queries and their results, and rows read by name.
	"dblink_build_sql_delete",
	"dblink_build_sql_insert",
	"dblink_build_sql_update",
	"dblink_cancel_query",
	"dblink_close",
	"dblink_connect_u",
	"dblink_current_query",
	"dblink_disconnect",
	"dblink_error_message",
	"dblink_fdw_validator",
	"dblink_fetch",
	"dblink_get_connections",
	"dblink_get_notify",
	"dblink_get_pkey",
	"dblink_get_result",
	"dblink_is_busy",
	"dblink_open",
	"dblink_send_query",
	# pg_cron runs scheduled SQL given as a string.
	"alter_job",
	"schedule",
	"schedule_in_database",
	"unschedule",
	# adminpack reaches the host's files.
	"pg_file_rename",
	"pg_file_sync",
	"pg_file_unlink",
	"pg_file_write",
	"pg_logdir_ls",
	"pg_read_file_old",
	"pg_rotate_logfile_old",
	# Server control and statistics writes from other PostgreSQL versions.
	"pg_start_backup",
	"pg_stop_backup",
	"pg_clear_attribute_stats",
	"pg_clear_relation_stats",
	"pg_restore_attribute_stats",
	"pg_restore_relation_stats",
	"pg_stat_reset_backend_stats",
	# Directory listings on the host, like the pg_ls_* functions already blocked.
	"pg_ls_logicalmapdir",
	"pg_ls_logicalsnapdir",
	"pg_ls_replslotdir",
	"pg_ls_summariesdir",
}

# Extension functions that run SQL given as a string, read or change a table named in a string,
# or reach the network. Each name was checked in the extension's install script or reference.
added_from_extensions := {
	# tablefunc 1.0 runs the query in its first argument.
	"connectby",
	"crosstab",
	"crosstab2",
	"crosstab3",
	"crosstab4",
	# xml2 1.1 and pageinspect 1.5 read a relation named in a string.
	"xpath_table",
	"get_raw_page",
	# PostGIS 3.5 alters, drops, creates or reads a table named in a string.
	"addgeometrycolumn",
	"dropgeometrycolumn",
	"dropgeometrytable",
	"populate_geometry_columns",
	"st_estimatedextent",
	"st_findextent",
	"st_fromflatgeobuftotable",
	"updategeometrysrid",
	# pgsql-http 1.6 and pg_net 0.14 send HTTP requests from the database host.
	"http",
	"http_delete",
	"http_get",
	"http_head",
	"http_patch",
	"http_post",
	"http_put",
	"http_reset_curlopt",
	"http_set_curlopt",
	# aws_s3 and aws_lambda on Amazon RDS and Aurora.
	"invoke",
	"query_export_to_s3",
	"table_import_from_s3",
	# pg_background 1.3 runs SQL in another session.
	"pg_background_detach",
	"pg_background_launch",
	"pg_background_result",
	# Citus 12.1 runs a command on other nodes.
	"master_run_on_worker",
	"run_command_on_all_nodes",
	"run_command_on_colocated_placements",
	"run_command_on_placements",
	"run_command_on_shards",
	"run_command_on_workers",
}

test_extension_functions_denied if {
	count(added_from_extensions) == 36
	every name in added_from_extensions {
		sql_denied_with(sprintf("SELECT %s(1)", [name]), "postgres.blocked_function")
		name in all_blocked_functions
	}
}

calls_through_extensions := {
	"SELECT * FROM crosstab('SELECT id, name, token FROM secrets.tokens') AS t(id int, a text)",
	"SELECT * FROM connectby('secrets.tokens', 'id', 'parent', '1', 0) AS t(id text, parent text, level int)",
	"SELECT * FROM xpath_table('id', 'body', 'secrets.tokens', '/a', 'true') AS t(id int, a text)",
	"SELECT get_raw_page('secrets.tokens', 0)",
	"SELECT DropGeometryTable('public', 'users')",
	"SELECT AddGeometryColumn('public', 'users', 'geom', 4326, 'POINT', 2)",
	"SELECT status FROM http_get('http://169.254.169.254/latest/meta-data/')",
	"SELECT net.http_post('https://example.com', '{}'::jsonb)",
	"SELECT * FROM aws_s3.query_export_to_s3('SELECT * FROM secrets.tokens', 'uri')",
	"SELECT * FROM aws_lambda.invoke('fn', '{}'::json)",
	"SELECT pg_background_launch('DROP TABLE users')",
	"SELECT run_command_on_workers('DROP TABLE users')",
}

test_calls_through_extensions_denied if {
	every sql in calls_through_extensions {
		sql_denied_with(sql, "postgres.blocked_function")
	}
}

test_functions_added_in_security_review_denied if {
	count(added_in_security_review) == 40
	every name in added_in_security_review {
		sql_denied_with(sprintf("SELECT %s(1)", [name]), "postgres.blocked_function")
		name in all_blocked_functions
	}
}
