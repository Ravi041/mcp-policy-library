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
