package mcp.lib

# How each kind of config value is described in a deny message.
config_kind_descriptions := {
	"boolean": "true or false",
	"string_list": "a list of strings",
	"string_list_map": "an object of string lists",
	"string_map": "an object of strings",
	"object": "an object",
}

is_string_list(value) if {
	is_array(value)
	every item in value {
		is_string(item)
	}
}

config_value_has_kind(value, "boolean") if is_boolean(value)

config_value_has_kind(value, "string_list") if is_string_list(value)

config_value_has_kind(value, "string_list_map") if {
	is_object(value)
	every list in value {
		is_string_list(list)
	}
}

config_value_has_kind(value, "string_map") if {
	is_object(value)
	every item in value {
		is_string(item)
	}
}

config_value_has_kind(value, "object") if is_object(value)

# Problems with a pack's config, given the kind each documented key must have. A value of the
# wrong kind would otherwise make rules that read it undefined, which switches deny lists off
# rather than on, so packs refuse every call while this is non-empty. Keys not in kinds are
# ignored, and an absent key keeps its default.
config_problems(config, _) := {"the configuration must be an object"} if not is_object(config)

config_problems(config, kinds) := problems if {
	is_object(config)
	problems := {sprintf("%s must be %s", [key, config_kind_descriptions[kind]]) |
		some key, value in config
		kind := kinds[key]
		not config_value_has_kind(value, kind)
	}
}
