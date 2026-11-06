package mcp_adapters.agentgateway_test

import data.mcp_adapters.agentgateway

config := {
	"baseline": {"allowed_servers": ["filesystem", "github"]},
	"filesystem": {"read_paths": ["/srv/app"], "write_paths": ["/srv/app/tmp"]},
	"github": {"allowed_repos": ["acme/web"], "allow_merge": true, "require_approval_tools": ["merge_pull_request"]},
}

alice := {"envoy.filters.http.jwt_authn": {"jwt_payload": {"sub": "alice@example.com", "iss": "dev", "aud": "mcp-gateway"}}}

check(method, body, extensions, metadata) := {
	"attributes": {
		"contextExtensions": extensions,
		"metadataContext": {"filterMetadata": metadata},
		"request": {
			"http": {"id": "req-1", "method": method, "path": "/filesystem/mcp", "headers": {"mcp-session-id": "s-1"}},
			"time": {"seconds": 1793944770, "nanos": 0},
		},
	},
	"parsed_body": body,
	"truncated_body": false,
}

call(server, tool, arguments) := check("POST", {"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": tool, "arguments": arguments}}, {"mcp_server": server}, alice)

rpc(method) := check("POST", {"jsonrpc": "2.0", "id": 1, "method": method, "params": {}}, {"mcp_server": "filesystem"}, alice)

response_for(request) := response if {
	response := agentgateway.response with input as request with data.mcp_config as config
}

refusal_body(request) := json.unmarshal(response_for(request).body)

refusal_code(request) := refusal_body(request).error.data.code

deny_codes(request) := {reason.code | some reason in refusal_body(request).error.data.decision.deny}

# --- tool calls go to the library -----------------------------------------------------------

test_allowed_tool_call_is_forwarded if {
	response_for(call("filesystem", "read_text_file", {"path": "/srv/app/README.md"})) == {"allowed": true}
}

test_denied_tool_call_is_a_jsonrpc_error_with_the_same_id if {
	request := call("filesystem", "read_text_file", {"path": "/srv/app/../../etc/passwd"})
	response := response_for(request)
	response.allowed == false
	response.http_status == 200
	response.headers["content-type"] == "application/json"
	body := json.unmarshal(response.body)
	body.jsonrpc == "2.0"
	body.id == 7
	body.error.code == -32001
	startswith(body.error.message, "refused by policy: filesystem.path_traversal: ")
	body.error.data.code == "adapter.denied"
	"filesystem.path_traversal" in deny_codes(request)
}

test_denied_message_lists_every_reason if {
	request := call("github", "delete_file", {"owner": "acme", "repo": "web", "path": ".github/workflows/ci.yml", "branch": "main", "message": "x"})
	{"github.protected_branch", "github.protected_path"} == deny_codes(request) & {"github.protected_branch", "github.protected_path"}
	contains(refusal_body(request).error.message, "github.protected_branch: ")
	contains(refusal_body(request).error.message, "github.protected_path: ")
}

test_approval_is_refused_and_says_so if {
	request := call("github", "merge_pull_request", {"owner": "acme", "repo": "web", "pullNumber": 1})
	refusal_code(request) == "adapter.approval_required"
	refusal_body(request).error.data.decision.require_approval == true
	count(refusal_body(request).error.data.decision.deny) == 0
}

test_tool_call_without_arguments_gets_an_empty_object if {
	request := check("POST", {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_allowed_directories"}}, {"mcp_server": "filesystem"}, alice)
	agentgateway.library_input.arguments == {} with input as request with data.mcp_config as config
	response_for(request) == {"allowed": true}
}

test_non_object_arguments_are_invalid_input if {
	request := call("filesystem", "read_text_file", "/srv/app/README.md")
	"main.invalid_input" in deny_codes(request)
}

test_tool_call_without_params_is_invalid_input if {
	request := check("POST", {"jsonrpc": "2.0", "id": 8, "method": "tools/call"}, {"mcp_server": "filesystem"}, alice)
	agentgateway.library_input.tool.name == "" with input as request with data.mcp_config as config
	"main.invalid_input" in deny_codes(request)
}

test_tool_call_with_non_object_params_is_invalid_input if {
	request := check("POST", {"jsonrpc": "2.0", "id": 8, "method": "tools/call", "params": ["read_text_file"]}, {"mcp_server": "filesystem"}, alice)
	"main.invalid_input" in deny_codes(request)
}

test_non_string_tool_name_is_invalid_input if {
	request := call("filesystem", 42, {"path": "/srv/app/README.md"})
	"main.invalid_input" in deny_codes(request)
}

# --- identity and routing come from the gateway, never the client ---------------------------

test_server_name_comes_from_the_route if {
	library_input := agentgateway.library_input with input as call("github", "get_me", {}) with data.mcp_config as config
	library_input.server == {"name": "github"}
}

test_missing_route_server_name_is_invalid_input if {
	"main.invalid_input" in deny_codes(check("POST", {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "read_text_file", "arguments": {"path": "/srv/app/a"}}}, {}, alice))
}

test_jwt_subject_is_the_principal if {
	library_input := agentgateway.library_input with input as call("filesystem", "read_text_file", {"path": "/srv/app/a"}) with data.mcp_config as config
	library_input.principal.id == "alice@example.com"
	library_input.principal.type == "user"
	library_input.principal.claims.iss == "dev"
}

test_route_service_principal_without_a_token if {
	request := check("POST", {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "read_text_file", "arguments": {"path": "/srv/app/a"}}}, {"mcp_server": "filesystem", "mcp_principal": "build-bot"}, {})
	library_input := agentgateway.library_input with input as request with data.mcp_config as config
	library_input.principal == {"id": "build-bot", "type": "service"}
	response_for(request) == {"allowed": true}
}

test_no_identity_is_invalid_input if {
	request := check("POST", {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "read_text_file", "arguments": {"path": "/srv/app/a"}}}, {"mcp_server": "filesystem"}, {})
	"main.invalid_input" in deny_codes(request)
}

test_non_string_subject_falls_back_to_the_route_principal if {
	metadata := {"envoy.filters.http.jwt_authn": {"jwt_payload": {"sub": 12}}}
	request := check("POST", {"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "read_text_file", "arguments": {"path": "/srv/app/a"}}}, {"mcp_server": "filesystem", "mcp_principal": "build-bot"}, metadata)
	agentgateway.library_input.principal.id == "build-bot" with input as request with data.mcp_config as config
}

test_input_uses_only_contract_fields if {
	library_input := agentgateway.library_input with input as call("filesystem", "read_text_file", {"path": "/srv/app/a"}) with data.mcp_config as config
	object.keys(library_input) == {"version", "request_id", "timestamp", "principal", "server", "tool", "arguments", "context"}
	library_input.version == "1.0"
	library_input.request_id == "req-1"
	library_input.timestamp == "2026-11-06T05:59:30Z"
	library_input.context == {"session": {"id": "s-1"}}
}

test_missing_time_and_session_are_left_out if {
	request := json.patch(call("filesystem", "read_text_file", {"path": "/srv/app/a"}), [
		{"op": "remove", "path": "/attributes/request/time"},
		{"op": "remove", "path": "/attributes/request/http/headers/mcp-session-id"},
	])
	library_input := agentgateway.library_input with input as request with data.mcp_config as config
	not "timestamp" in object.keys(library_input)
	not "context" in object.keys(library_input)
	response_for(request) == {"allowed": true}
}

# --- other MCP traffic -----------------------------------------------------------------------

test_session_setup_and_listing_pass if {
	every method in ["initialize", "ping", "tools/list"] {
		response_for(rpc(method)) == {"allowed": true}
	}
}

test_notifications_pass if {
	response_for(check("POST", {"jsonrpc": "2.0", "method": "notifications/initialized"}, {"mcp_server": "filesystem"}, alice)) == {"allowed": true}
}

test_client_reply_to_a_server_request_passes if {
	response_for(check("POST", {"jsonrpc": "2.0", "id": 9, "result": {}}, {"mcp_server": "filesystem"}, alice)) == {"allowed": true}
}

test_event_stream_and_session_end_pass if {
	every method in ["GET", "DELETE"] {
		response_for(check(method, null, {"mcp_server": "filesystem"}, alice)) == {"allowed": true}
	}
}

test_resources_and_prompts_are_refused if {
	every method in ["resources/read", "resources/list", "prompts/get", "completion/complete"] {
		refusal_code(rpc(method)) == "adapter.method_not_allowed"
		refusal_body(rpc(method)).id == 1
	}
}

test_batch_is_refused if {
	request := check("POST", [{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "read_text_file", "arguments": {"path": "/srv/app/a"}}}], {"mcp_server": "filesystem"}, alice)
	refusal_code(request) == "adapter.invalid_request"
	refusal_body(request).id == null
}

test_post_without_a_body_is_refused if {
	refusal_code(check("POST", null, {"mcp_server": "filesystem"}, alice)) == "adapter.invalid_request"
}

test_truncated_body_is_refused_even_for_an_allowed_call if {
	request := json.patch(call("filesystem", "read_text_file", {"path": "/srv/app/README.md"}), [{"op": "replace", "path": "/truncated_body", "value": true}])
	refusal_code(request) == "adapter.body_too_large"
	not refusal_body(request).error.data.decision
}

test_truncated_initialize_is_refused if {
	request := json.patch(rpc("initialize"), [{"op": "replace", "path": "/truncated_body", "value": true}])
	refusal_code(request) == "adapter.body_too_large"
}
