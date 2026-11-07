package mcp.lib_test

import data.mcp.lib

kinds := {
	"flag": "boolean",
	"names": "string_list",
	"per_server": "string_list_map",
	"aliases": "string_map",
	"window": "object",
}

test_valid_config_has_no_problems if {
	config := {
		"flag": false,
		"names": ["a", "b"],
		"per_server": {"wiki": ["search"]},
		"aliases": {"gh-prod": "github"},
		"window": {"timezone": "UTC"},
	}
	lib.config_problems(config, kinds) == set()
}

test_empty_values_are_valid if {
	lib.config_problems({"names": [], "per_server": {}, "aliases": {}, "window": {}}, kinds) == set()
}

test_absent_and_unknown_keys_are_ignored if {
	lib.config_problems({}, kinds) == set()
	lib.config_problems({"something_else": "x"}, kinds) == set()
}

# A string where a list belongs is the mistake that used to switch a deny list off.
test_string_instead_of_list if {
	lib.config_problems({"names": "main"}, kinds) == {"names must be a list of strings"}
}

test_list_with_a_non_string if {
	lib.config_problems({"names": ["main", 1]}, kinds) == {"names must be a list of strings"}
}

test_string_instead_of_boolean if {
	lib.config_problems({"flag": "true"}, kinds) == {"flag must be true or false"}
	lib.config_problems({"flag": 1}, kinds) == {"flag must be true or false"}
	lib.config_problems({"flag": null}, kinds) == {"flag must be true or false"}
}

test_bad_map_values if {
	lib.config_problems({"per_server": {"wiki": "search"}}, kinds) == {"per_server must be an object of string lists"}
	lib.config_problems({"per_server": ["search"]}, kinds) == {"per_server must be an object of string lists"}
	lib.config_problems({"aliases": {"gh-prod": ["github"]}}, kinds) == {"aliases must be an object of strings"}
	lib.config_problems({"window": "9-5"}, kinds) == {"window must be an object"}
}

test_every_bad_key_is_reported if {
	count(lib.config_problems({"flag": "yes", "names": "x", "window": 1}, kinds)) == 3
}

test_config_that_is_not_an_object if {
	lib.config_problems("main", kinds) == {"the configuration must be an object"}
	lib.config_problems(["main"], kinds) == {"the configuration must be an object"}
	lib.config_problems(null, kinds) == {"the configuration must be an object"}
}
