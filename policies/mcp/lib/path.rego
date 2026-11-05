# METADATA
# title: Shared helpers
# description: Pure helpers for path checks, reasons, config flags and time windows. They read only their arguments.
package mcp.lib

# Non-empty path segments, with "." removed. ".." is kept so callers can reject it.
path_segments(path) := [segment |
	some segment in split(path, "/")
	segment != ""
	segment != "."
]

path_is_absolute(path) if {
	is_string(path)
	startswith(path, "/")
}

path_has_traversal(path) if ".." in split(path, "/")

path_has_traversal(path) if contains(path, `\`)

# Encoded dots and separators have no business in a path an agent sends.
path_has_traversal(path) if regex.match(`(?i)%(2e|2f|5c)`, path)

path_has_invalid_chars(path) if regex.match(`[\x00-\x1f\x7f]`, path)

# Kernel-provided links that reach outside the visible path, whatever its prefix.
path_has_indirection(path) if regex.match(`^/+proc/+(self|thread-self|[0-9]+)/+(root|cwd|fd|exe|task)(/|$)`, path)

path_has_indirection(path) if regex.match(`^/+dev/+fd(/|$)`, path)

path_is_safe(path) if {
	path_is_absolute(path)
	not path_has_traversal(path)
	not path_has_invalid_chars(path)
	not path_has_indirection(path)
}

# Compares whole segments, so /srv/app never matches /srv/app-secrets.
path_within(path, directory) if {
	path_is_safe(path)
	path_is_safe(directory)
	path_parts := path_segments(path)
	directory_parts := path_segments(directory)
	array.slice(path_parts, 0, count(directory_parts)) == directory_parts
}

path_within_any(path, directories) if {
	some directory in directories
	path_within(path, directory)
}

# Case-insensitive on purpose: this backs deny lists, and a case-insensitive
# filesystem must not let .ENV slip past a rule for .env.
path_matches_glob(path, pattern) if {
	canonical := lower(concat("/", ["", concat("/", path_segments(path))]))
	some candidate in [canonical, concat("", [canonical, "/"])]
	glob.match(lower(pattern), ["/"], candidate)
}

path_matches_any_glob(path, patterns) if {
	some pattern in patterns
	path_matches_glob(path, pattern)
}
