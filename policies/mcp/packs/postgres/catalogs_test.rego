package mcp.packs.postgres_test

import data.mcp.packs.postgres

# Catalogs with password hashes or connection passwords, and the storage behind other tables.
sensitive_catalog_queries := {
	"SELECT rolname, rolpassword FROM pg_authid",
	"SELECT * FROM pg_catalog.pg_shadow",
	`SELECT * FROM "pg_shadow"`,
	"SELECT * FROM PG_USER_MAPPINGS",
	"SELECT umoptions FROM pg_user_mapping",
	"SELECT subconninfo FROM pg_subscription",
	"SELECT data FROM pg_largeobject",
	"SELECT * FROM pg_toast.pg_toast_16385",
	`SELECT * FROM "pg_toast" . pg_toast_16385`,
	"WITH x AS (SELECT * FROM pg_shadow) SELECT * FROM x",
}

test_sensitive_catalogs_denied if {
	every sql in sensitive_catalog_queries {
		sql_denied_with(sql, "postgres.sensitive_catalog")
	}
}

test_toast_schema_denied_on_metadata_tools if {
	denied_with(call("list_objects", {"schema_name": "pg_toast"}), "postgres.sensitive_catalog")
}

test_catalogs_without_secrets_still_allowed if {
	every sql in [
		"SELECT rolname FROM pg_roles",
		"SELECT usename FROM pg_user",
		"SELECT * FROM pg_stat_subscription",
		"SELECT * FROM pg_catalog.pg_tables",
		"SELECT 'pg_shadow' AS name",
		"SELECT pg_shadow_count FROM metrics",
	] {
		allowed(sql_call(sql))
	}
}

# Other sessions' statement text holds the literals they sent, including values written to
# a denied schema. On PostgreSQL 17.11, pg_stat_activity returned an idle connection's last
# statement, INSERT INTO secrets.api_keys VALUES (..., 'sk_live_...'), through agentgateway.
activity_queries := {
	"SELECT query FROM pg_stat_activity",
	"SELECT query FROM pg_catalog.pg_stat_activity WHERE state = 'idle'",
	`SELECT query FROM "pg_stat_activity"`,
	"SELECT * FROM PG_STAT_ACTIVITY",
	"SELECT * FROM pg_stat_get_activity(NULL)",
	"SELECT pg_stat_get_backend_activity(b) FROM pg_stat_get_backend_idset() AS b",
	"SELECT query FROM pg_stat_statements",
	"SELECT * FROM pg_stat_statements(true)",
}

test_activity_views_denied_with_denied_schemas if {
	every sql in activity_queries {
		not allowed_with(sql_call(sql), schema_cfg)
		"postgres.activity_not_allowed" in codes(postgres.deny) with input as sql_call(sql)
			with data.mcp_config.postgres as schema_cfg
	}
}

test_activity_views_allowed_without_denied_schemas if {
	every sql in activity_queries {
		allowed_with(sql_call(sql), {})
	}
}

test_activity_names_in_strings_are_still_text if {
	allowed_with(sql_call("SELECT 'pg_stat_activity' AS name"), schema_cfg)
}
