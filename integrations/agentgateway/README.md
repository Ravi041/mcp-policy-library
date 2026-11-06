# agentgateway

Run the policy library inside [agentgateway](https://agentgateway.dev), an open-source MCP gateway. agentgateway asks OPA before it forwards each MCP request, and a small adapter policy turns that request into the library's input.

Verified against agentgateway v1.7.0, OPA-Envoy v1.22.0 and mcp-policy-library v0.1.0. For a step-by-step walkthrough with real MCP servers, see [docs/try-it-with-gateways.md](../../docs/try-it-with-gateways.md).

```
MCP client --Bearer JWT--> agentgateway --ext_authz gRPC--> OPA-Envoy                      --> MCP server
                            jwtAuth                          mcp_adapters/agentgateway        (only if allowed)
                            extAuthz                           -> data.mcp.main.decision
```

## Files

| File | What it is |
|---|---|
| [`policy/mcp_adapters/agentgateway/adapter.rego`](policy/mcp_adapters/agentgateway/adapter.rego) | The adapter. It builds the library input, asks `data.mcp.main.decision` and answers in the OPA-Envoy format. Tested by `make test`. |
| [`agentgateway.template.yaml`](agentgateway.template.yaml) | Gateway configuration: one route per MCP server, each with `jwtAuth` and `extAuthz` |
| [`try.sh`](try.sh) | Starts OPA, the gateway, MCP servers and Postgres, runs 29 checks, and stops everything |
| [`mcp-client.sh`](mcp-client.sh) | A minimal MCP client over Streamable HTTP, using curl |
| [`dev-token.sh`](dev-token.sh) | Creates a local signing key, a JWKS and short-lived tokens. For local testing only. |
| [`install.sh`](install.sh), [`tools.sha256`](tools.sha256) | Installs pinned agentgateway, OPA-Envoy and GitHub MCP server binaries into `.bin/`, checking each checksum |

## How the adapter builds the input

agentgateway sends an Envoy `CheckRequest` for every HTTP request on an MCP route. With `includeRequestBody`, OPA-Envoy parses the JSON-RPC body into `input.parsed_body`.

| Library input | Source | Why it can be trusted |
|---|---|---|
| `principal.id` | `sub` of the verified JWT, at `metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload` | agentgateway checks the signature, issuer, audience and expiry before calling OPA, and passes on only verified claims. |
| `principal` without a token | `contextExtensions.mcp_principal`, if a route sets it, as a `service` principal | It is set in gateway configuration. |
| `server.name` | `contextExtensions.mcp_server`, set per route | It comes from gateway configuration, so the agent cannot pick the pack that judges it. |
| `tool.name`, `arguments` | `parsed_body.params.name`, `parsed_body.params.arguments` | Passed exactly as sent. Missing arguments become `{}`. |
| `timestamp` | `attributes.request.time` | It is the time the gateway received the request. |
| `request_id` | `attributes.request.http.id` | |
| `context.session.id` | the `Mcp-Session-Id` header | |

A missing identity or server name produces an empty field, and the library refuses the call with `main.invalid_input`.

## What the adapter lets through

| Request | Result |
|---|---|
| `tools/call` | Allowed only if `data.mcp.main.decision` has `allow: true` |
| `initialize`, `ping`, `tools/list`, any `notifications/*`, replies to server requests | Allowed. They run no tool. |
| `GET` (event stream), `DELETE` (end session) | Allowed. They carry no client message. |
| `resources/*`, `prompts/*`, `completion/*` and any other method | Refused with `adapter.method_not_allowed`, because tool rules cannot see them. The filesystem server, for example, serves files through `resources/read`. |
| A JSON-RPC batch, or a POST without a JSON body | Refused with `adapter.invalid_request` |
| A body larger than `includeRequestBody.maxRequestBytes` | Refused with `adapter.body_too_large`, because OPA saw only part of it |

## What the agent sees

A refusal is an HTTP 200 carrying a JSON-RPC error. MCP clients show it as the tool call's error, so the agent can read why and adjust:

```json
{
  "jsonrpc": "2.0",
  "id": 9,
  "error": {
    "code": -32001,
    "message": "refused by policy: github.protected_branch: branch \"main\" is protected; open a pull request instead",
    "data": {
      "code": "adapter.denied",
      "decision": {"allow": false, "deny": [{"code": "github.protected_branch", "message": "...", "pack": "github"}], "...": "..."}
    }
  }
}
```

| `error.data.code` | Meaning |
|---|---|
| `adapter.denied` | The library refused the call. `error.data.decision` is the full decision. |
| `adapter.approval_required` | The library wants human approval. agentgateway has no approval step, so the call is refused. |
| `adapter.method_not_allowed` | An MCP method other than the ones listed above |
| `adapter.invalid_request` | A batch, or no JSON-RPC message in the body |
| `adapter.body_too_large` | The body was truncated before OPA saw it |

If OPA is down or times out, agentgateway refuses the request with HTTP 403 and never forwards it. `try.sh` checks this.

## Running it in your own setup

1. Load three bundles into OPA-Envoy: the policy bundle, `integrations/agentgateway/policy/`, and your configuration with root `mcp_config`. Set `plugins.envoy_ext_authz_grpc.path=mcp_adapters/agentgateway/response`. `start_opa` in [`try.sh`](try.sh) shows the full command.
2. For each MCP server, add a route with:
   - authentication, such as `jwtAuth` against your identity provider's JWKS;
   - `extAuthz` with `protocol.grpc.context.mcp_server` set to the pack name or a `server_aliases` key;
   - `includeRequestBody` large enough for your biggest tool call.
3. Leave `protocol.grpc.metadata` unset. When it is set, agentgateway sends only those values and no longer forwards the verified JWT claims.

## Limitations

- **No tool annotations.** agentgateway's ext_authz request does not carry the server's tool annotations, so the baseline `destructive_tool` rule never fires here. Tool-name rules and allowlists are unaffected.
- **One server per route.** If several targets are multiplexed on one route, agentgateway prefixes tool names with the target name, and `mcp_server` can name only one pack. Give each server its own route, as the template does.
- **Sensitive decision logs.** `try.sh` turns on console decision logs, which include tool arguments such as file contents and SQL. In production, mask them with a decision-log mask policy or send them to a protected sink.
- **No approval step.** Approval becomes a refusal.

## Deploying it safely

These were checked in a penetration test against agentgateway v1.7.0 and OPA-Envoy v1.22.0.

- **Keep agents off the gateway's host.** agentgateway's admin endpoint, `localhost:15000` by default, serves the whole configuration, including backend credentials such as `GITHUB_PERSONAL_ACCESS_TOKEN` and database passwords. An agent with a shell on the same host or in the same network namespace can read them and call the backends directly, without passing the policy. It can be moved with `config.adminAddr` but not turned off. The template binds the stats and readiness ports to localhost as well.
- **Keep agents away from OPA's HTTP API.** OPA refuses writes under a bundle's roots, so a local process could not change `mcp`, `mcp_config` or `mcp_adapters/agentgateway`. It could still read every configuration value and load unrelated policies. Bind the API to localhost, as `try.sh` does, and add [authentication](https://www.openpolicyagent.org/docs/security) where other processes share the host.
- **Give each MCP server only the directories the policy allows.** The filesystem server resolves symlinks against its own allowed directories, and the policy cannot see links. In the template, both use `workspace/projects`.
- **What the test found the adapter refuses.** Requests with no JSON content type, batches, methods in another case and `tools/call` sent as a notification are refused. agentgateway itself rejected bodies that were gzip-compressed, started with a byte-order mark, were larger than `maxRequestBytes`, or repeated `method` or a key inside `params`.
- **Porting to another gateway.** Check that it parses JSON the way OPA does. OPA keeps the last of two duplicate keys. A gateway or server that keeps the first would forward a different call from the one the policy judged.
