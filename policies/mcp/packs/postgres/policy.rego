# METADATA
# title: Postgres pack
# description: Best-effort read-only guard for Postgres MCP servers. It does not replace database permissions.
package mcp.packs.postgres

import data.mcp.lib

pack_name := "postgres"

default config := {}

config := data.mcp_config.postgres

default tool_name := "<missing>"

tool_name := input.tool.name

# query is the archived reference server; execute_sql and explain_query are postgres-mcp.
sql_tools := {"query", "execute_sql", "explain_query"}

schema_tools := {"list_objects", "get_object_details"}

metadata_tools := schema_tools | {"list_schemas"}

# Off unless listed in allowed_optional_tools.
optional_tools := {"get_top_queries", "analyze_db_health", "analyze_workload_indexes"}

known_tools := (sql_tools | metadata_tools) | optional_tools

read_starters := {"SELECT", "SHOW", "VALUES", "TABLE", "EXPLAIN", "WITH"}

write_starters := {"INSERT", "UPDATE", "DELETE", "MERGE"}

ddl_starters := {
	"ALTER",
	"ANALYZE",
	"CLUSTER",
	"COMMENT",
	"CREATE",
	"DROP",
	"GRANT",
	"REFRESH",
	"REINDEX",
	"REVOKE",
	"SECURITY",
	"TRUNCATE",
	"VACUUM",
}

write_keywords := {"INSERT", "UPDATE", "DELETE", "MERGE"}

ddl_keywords := {"ALTER", "CREATE", "DROP", "GRANT", "REVOKE", "TRUNCATE"}

# Functions with side effects, that reach the host, or that run SQL hidden in a string.
default_blocked_functions := {
	"dblink",
	"dblink_connect",
	"dblink_exec",
	"cursor_to_xml",
	"lo_create",
	"lo_export",
	"lo_from_bytea",
	"lo_import",
	"lo_put",
	"lo_unlink",
	"nextval",
	"pg_cancel_backend",
	"pg_create_restore_point",
	"pg_ls_archive_statusdir",
	"pg_ls_dir",
	"pg_ls_logdir",
	"pg_ls_tmpdir",
	"pg_ls_waldir",
	"pg_read_binary_file",
	"pg_read_file",
	"pg_reload_conf",
	"pg_rotate_logfile",
	"pg_sleep",
	"pg_sleep_for",
	"pg_sleep_until",
	"pg_stat_file",
	"pg_switch_wal",
	"pg_terminate_backend",
	"query_to_xml",
	"query_to_xml_and_xmlschema",
	"query_to_xmlschema",
	"set_config",
	"setval",
	"ts_stat",
}

default extra_blocked_functions := []

extra_blocked_functions := config.extra_blocked_functions

blocked_functions := default_blocked_functions | lib.lower_set(extra_blocked_functions)

default denied_schema_list := []

denied_schema_list := config.denied_schemas

denied_schemas := lib.lower_set(denied_schema_list)

sql := input.arguments.sql if tool_name in sql_tools

sql_is_present if {
	is_string(sql)
	trim_space(sql) != ""
}

# Tokens are matched left to right, so a quote inside a comment, or dashes inside a
# string, cannot start a new token. Group 2 captures a quoted identifier's name.
token_pattern := `('(?:[^']|'')*'|--[^\r\n]*)|"((?:[^"]|"")*)"`

# Strings, comments and quoted identifiers replaced by spaces. Used for keywords.
code_with_no_tokens := regex.replace(sql, token_pattern, " ") if sql_is_present

# Strings and comments removed, with identifiers unquoted. Used for function and schema names.
code_with_identifiers := regex.replace(sql, token_pattern, "${2} ") if sql_is_present

# Each of these parses differently in PostgreSQL than in the scanner above, so any of
# them could hide a statement. Refusing them is what keeps the checks below honest.
sql_is_unreadable if contains(sql, `\`) # E'' escapes and standard_conforming_strings

sql_is_unreadable if regex.match(`\$[A-Za-z0-9_]*\$`, sql) # dollar quoting

sql_is_unreadable if regex.match(`(?i)\bu&`, sql) # Unicode escapes

sql_is_unreadable if regex.match(`\x00`, sql)

sql_is_unreadable if contains(code_with_no_tokens, "'") # unterminated string

sql_is_unreadable if contains(code_with_no_tokens, `"`) # unterminated identifier

sql_is_unreadable if contains(code_with_no_tokens, "/*") # block comments nest in PostgreSQL

sql_is_unreadable if contains(code_with_no_tokens, "*/")

sql_is_readable if {
	sql_is_present
	not sql_is_unreadable
}

code := trim_right(upper(code_with_no_tokens), "; \t\r\n") if sql_is_readable

is_single_statement if {
	sql_is_readable
	not contains(code, ";")
}

keywords := {word | some word in regex.find_n(`[A-Z_][A-Z0-9_$]*`, code, -1)} if is_single_statement

default first_keyword := ""

first_keyword := regex.find_n(`^[A-Z_]+`, trim_space(code), 1)[0] if is_single_statement

has_write_keyword if count(keywords & write_keywords) > 0

has_ddl_keyword if count(keywords & ddl_keywords) > 0

# DDL is checked first, so a statement that does both is held to the stricter flag.
statement_class := "ddl" if {
	first_keyword in ddl_starters
} else := "ddl" if {
	first_keyword in (read_starters | write_starters)
	has_ddl_keyword
} else := "ddl" if {
	first_keyword in read_starters
	"INTO" in keywords
	not has_write_keyword
} else := "write" if {
	first_keyword in write_starters
} else := "write" if {
	first_keyword in read_starters
	has_write_keyword
} else := "read" if {
	first_keyword in read_starters
} else := "other" if {
	is_single_statement
}

called_functions contains lower(match[1]) if {
	sql_is_readable
	some match in regex.find_all_string_submatch_n(`([A-Za-z_][A-Za-z0-9_$]*)\s*\(`, code_with_identifiers, -1)
}

referenced_schemas contains lower(match[1]) if {
	sql_is_readable
	some match in regex.find_all_string_submatch_n(`([A-Za-z_][A-Za-z0-9_$]*)\s*\.`, code_with_identifiers, -1)
}

referenced_schemas contains lower(schema) if {
	tool_name in schema_tools
	schema := input.arguments.schema_name
	is_string(schema)
}

schema_name_is_string if is_string(input.arguments.schema_name)

optional_tool_is_enabled if tool_name in config.allowed_optional_tools

class_is_permitted if statement_class == "read"

class_is_permitted if {
	statement_class == "write"
	lib.flag_enabled(config, "allow_writes")
}

class_is_permitted if {
	statement_class == "ddl"
	lib.flag_enabled(config, "allow_ddl")
}

deny contains lib.deny_reason(
	pack_name,
	"tool_not_supported",
	sprintf("tool %q is not known to this pack, or takes SQL it cannot inspect", [tool_name]),
) if {
	not tool_name in known_tools
}

deny contains lib.deny_reason(
	pack_name,
	"optional_tool_not_allowed",
	sprintf("tool %q is off unless listed in allowed_optional_tools", [tool_name]),
) if {
	tool_name in optional_tools
	not optional_tool_is_enabled
}

deny contains lib.deny_reason(
	pack_name,
	"missing_argument",
	sprintf("tool %q needs a non-empty string sql argument", [tool_name]),
) if {
	tool_name in sql_tools
	not sql_is_present
}

deny contains lib.deny_reason(
	pack_name,
	"missing_argument",
	sprintf("tool %q needs a string schema_name argument", [tool_name]),
) if {
	tool_name in schema_tools
	not schema_name_is_string
}

deny contains lib.deny_reason(
	pack_name,
	"unparseable_sql",
	"the SQL uses syntax this pack cannot read reliably, such as backslashes, dollar quotes or block comments",
) if {
	sql_is_present
	sql_is_unreadable
}

deny contains lib.deny_reason(
	pack_name,
	"multiple_statements",
	"only one statement per call is allowed",
) if {
	sql_is_readable
	not is_single_statement
}

deny contains lib.deny_reason(
	pack_name,
	"write_not_allowed",
	"statements that change data are off unless allow_writes is set",
) if {
	statement_class == "write"
	not lib.flag_enabled(config, "allow_writes")
}

deny contains lib.deny_reason(
	pack_name,
	"ddl_not_allowed",
	"statements that change schema or permissions are off unless allow_ddl is set",
) if {
	statement_class == "ddl"
	not lib.flag_enabled(config, "allow_ddl")
}

deny contains lib.deny_reason(
	pack_name,
	"statement_not_allowed",
	sprintf("statement type %q is never allowed", [first_keyword]),
) if {
	statement_class == "other"
}

deny contains lib.deny_reason(
	pack_name,
	"unbounded_write",
	"UPDATE and DELETE need a WHERE clause unless allow_unbounded_writes is set",
) if {
	first_keyword in {"UPDATE", "DELETE"}
	not "WHERE" in keywords
	not lib.flag_enabled(config, "allow_unbounded_writes")
}

deny contains lib.deny_reason(
	pack_name,
	"explain_analyze",
	"EXPLAIN ANALYZE runs the statement, so it is not allowed",
) if {
	first_keyword == "EXPLAIN"
	count(keywords & {"ANALYZE", "ANALYSE"}) > 0
}

deny contains lib.deny_reason(
	pack_name,
	"explain_analyze",
	"explain_query with analyze runs the statement, so it is not allowed",
) if {
	tool_name == "explain_query"
	input.arguments.analyze != false
}

deny contains lib.deny_reason(
	pack_name,
	"blocked_function",
	sprintf("function %q is blocked", [name]),
) if {
	some name in (called_functions & blocked_functions)
}

deny contains lib.deny_reason(
	pack_name,
	"denied_schema",
	sprintf("schema %q is denied", [name]),
) if {
	some name in (referenced_schemas & denied_schemas)
}

default allow := false

allow if {
	tool_name in sql_tools
	class_is_permitted
	count(deny) == 0
}

allow if {
	tool_name in metadata_tools
	count(deny) == 0
}

allow if {
	tool_name in optional_tools
	count(deny) == 0
}

default require_approval := false

require_approval if {
	lib.flag_enabled(config, "require_approval_for_writes")
	statement_class in {"write", "ddl"}
}

audit_tags contains "postgres:read" if statement_class == "read"

audit_tags contains "postgres:write" if statement_class == "write"

audit_tags contains "postgres:ddl" if statement_class == "ddl"

audit_tags contains "postgres:read" if tool_name in metadata_tools

audit_tags contains "postgres:read" if tool_name in optional_tools
