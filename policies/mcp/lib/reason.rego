package mcp.lib

# Builds a deny reason with a stable code of the form <pack>.<reason>.
deny_reason(pack, code, message) := {
	"code": sprintf("%s.%s", [pack, code]),
	"message": message,
	"pack": pack,
}

# True only for a literal true, so a stray "true" or 1 in config never opens access.
flag_enabled(config, name) if config[name] == true

# Lowercases the strings in a list. Anything else contributes nothing.
lower_set(values) := {lower(value) |
	is_array(values)
	some value in values
	is_string(value)
}
