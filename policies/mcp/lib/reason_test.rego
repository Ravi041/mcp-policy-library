package mcp.lib_test

import data.mcp.lib

test_deny_reason_prefixes_code_with_pack if {
	lib.deny_reason("github", "protected_branch", "nope") == {
		"code": "github.protected_branch",
		"message": "nope",
		"pack": "github",
	}
}

test_flag_true_only_for_literal_true if {
	lib.flag_enabled({"a": true}, "a")
	not lib.flag_enabled({"a": "true"}, "a")
	not lib.flag_enabled({"a": 1}, "a")
	not lib.flag_enabled({"a": false}, "a")
	not lib.flag_enabled({}, "a")
}

test_lower_set_lowercases_strings if lib.lower_set(["Acme", "b"]) == {"acme", "b"}

test_lower_set_skips_non_strings if lib.lower_set(["a", 1, null]) == {"a"}

test_lower_set_of_non_list_is_empty if lib.lower_set("acme") == set()
