# METADATA
# title: agentgateway adapter
# description: >-
#   Turns the Envoy ext_authz check that agentgateway sends for each MCP request into the
#   library's input, asks data.mcp.main.decision, and answers in the OPA-Envoy response format.
#   This file is integration code. It is not part of the policy bundle and is loaded beside it.
package mcp_adapters.agentgateway

import data.mcp.main

request := input.attributes.request.http

body := input.parsed_body

rpc_method := body.method

# Client messages that never run a tool. Every other JSON-RPC method is refused, which also
# covers resources/read: the filesystem server serves files through it, and tool rules cannot
# see it.
passthrough_methods := {"initialize", "ping", "tools/list"}

# --- What kind of HTTP request this is -------------------------------------------------------

# GET opens the server-to-client event stream and DELETE ends the session. Neither carries a
# client message, and the gateway has already authenticated the caller.
is_stream_or_session_end if request.method in {"GET", "DELETE"}

body_is_message if is_object(body)

is_notification if {
	body_is_message
	startswith(rpc_method, "notifications/")
}

# A client's reply to a server request, such as sampling or elicitation, has no method.
is_client_reply if {
	body_is_message
	not body.method
	body.id
}

is_passthrough if {
	body_is_message
	rpc_method in passthrough_methods
}

is_tool_call if {
	body_is_message
	rpc_method == "tools/call"
}

# --- Building the library input --------------------------------------------------------------

default params := {}

params := body.params if is_object(body.params)

# MCP makes arguments optional. A value that is present but not an object is passed on as is,
# so the router answers main.invalid_input.
default tool_arguments := {}

tool_arguments := params.arguments if "arguments" in object.keys(params)

default tool_name := ""

tool_name := params.name

# The server name comes from the route in the gateway configuration, never from the client.
default server_name := ""

server_name := input.attributes.contextExtensions.mcp_server

jwt_claims := input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload

# A helper rule, because `not is_string(x)` is undefined rather than true when x is missing.
has_jwt_subject if is_string(jwt_claims.sub)

# A verified token names a user. Without one, a route may name a fixed service principal.
default principal := {"id": "", "type": "service"}

principal := {"id": jwt_claims.sub, "type": "user", "claims": jwt_claims} if has_jwt_subject

principal := {"id": service_principal, "type": "service"} if {
	not has_jwt_subject
	service_principal := input.attributes.contextExtensions.mcp_principal
}

received_at := input.attributes.request.time

received_ns := (received_at.seconds * 1000000000) + object.get(received_at, "nanos", 0)

default timestamp_fields := {}

timestamp_fields := {"timestamp": time.format(received_ns)}

default session_fields := {}

session_fields := {"context": {"session": {"id": request.headers["mcp-session-id"]}}}

library_input := object.union_n([
	{
		"version": "1.0",
		"request_id": object.get(request, "id", ""),
		"principal": principal,
		"server": {"name": server_name},
		"tool": {"name": tool_name},
		"arguments": tool_arguments,
	},
	timestamp_fields,
	session_fields,
])

# The adapter's input is the ext_authz check, so the library is asked with its own input.
decision := library_decision if {
	# regal ignore:with-outside-test-context
	library_decision := main.decision with input as library_input
}

is_checked_tool_call if {
	not input.truncated_body == true
	is_tool_call
}

# --- The answer --------------------------------------------------------------------------------

default refusal := {
	"code": "adapter.method_not_allowed",
	"message": "this MCP method is not allowed through the policy gateway",
}

refusal := {
	"code": "adapter.body_too_large",
	"message": "the request body was larger than the gateway sends for authorization",
} if input.truncated_body == true

refusal := {
	"code": "adapter.invalid_request",
	"message": "the request body is not a single JSON-RPC message",
} if {
	not input.truncated_body == true
	not body_is_message
}

refusal := {
	"code": "adapter.approval_required",
	"message": "this call needs human approval, and this gateway has no approval step",
} if {
	is_checked_tool_call
	decision.require_approval == true
}

refusal := {"code": "adapter.denied", "message": concat("; ", reasons)} if {
	is_checked_tool_call
	not decision.require_approval == true
	reasons := [sprintf("%s: %s", [reason.code, reason.message]) | some reason in decision.deny]
}

default allowed := false

allowed if is_stream_or_session_end

allowed if {
	not input.truncated_body == true
	is_notification
}

allowed if {
	not input.truncated_body == true
	is_client_reply
}

allowed if {
	not input.truncated_body == true
	is_passthrough
}

allowed if {
	is_checked_tool_call
	decision.allow == true
}

default request_id := null

request_id := body.id if body_is_message

error_data := {"code": refusal.code, "decision": decision} if is_checked_tool_call

error_data := {"code": refusal.code} if not is_checked_tool_call

# METADATA
# description: >-
#   The OPA-Envoy answer. A refusal is an HTTP 200 carrying a JSON-RPC error, which MCP clients
#   show to the agent as the tool call's error, so the agent learns why it was refused.
# entrypoint: true
response := {"allowed": true} if allowed

response := {
	"allowed": false,
	"http_status": 200,
	"headers": {"content-type": "application/json"},
	"body": json.marshal({
		"jsonrpc": "2.0",
		"id": request_id,
		"error": {
			"code": -32001,
			"message": sprintf("refused by policy: %s", [refusal.message]),
			"data": error_data,
		},
	}),
} if not allowed
