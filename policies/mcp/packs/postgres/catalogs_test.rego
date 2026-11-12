package mcp.packs.postgres_test

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
