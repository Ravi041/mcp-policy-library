# Integrations

The policies know nothing about any gateway. An integration is the small adapter that turns a gateway's view of a tool call into the input the policies read, asks OPA, and enforces the answer. Everything gateway-specific lives here, never in `policies/`.

| Integration | Status |
|---|---|
| [`agentgateway/`](agentgateway/README.md) | The agentgateway MCP gateway, through OPA-Envoy ext_authz. The adapter policy is tested by `make test`; [`try.sh`](agentgateway/try.sh) runs it with real MCP servers. |
| [`opa-sidecar/`](opa-sidecar/README.md) | OPA over HTTP with Docker Compose. Tested by `make e2e-docker`. |
| [`kavrynt/`](kavrynt/README.md) | Documentation only, until Kavrynt's loading API is confirmed. |

## Writing an adapter for any gateway

### 1. Build the input

Map each `tools/call` request onto [`schemas/input.schema.json`](../schemas/input.schema.json). The [input contract](../docs/input-contract.md) explains each field.

- **`principal`** comes from authenticated identity: your session, token or mTLS identity. Never take it from the agent or the tool arguments.
- **`server.name`** comes from your gateway's configuration for that upstream server. It is how the router picks a pack, so an agent must never be able to choose it. If your name differs from a pack name, map it with `data.mcp_config.main.server_aliases`.
- **`tool.annotations`** come from the server's `tools/list` response, if you have it. They can only restrict access.
- **`arguments`** are passed exactly as the agent sent them. Do not normalize paths or SQL first, because the packs check the raw form.
- **`timestamp`** is the time your gateway received the call. Time windows read only this field.
- **Anything gateway-specific** goes in `server.labels` or `context.labels`. The schema rejects unknown fields everywhere else.

Validate the input against the schema in your tests. `make fixtures` shows one way to do it with OPA alone.

### 2. Ask OPA

Query `data.mcp.main.decision`, with `POST /v1/data/mcp/main/decision` and body `{"input": ...}`, or embed OPA as a library and evaluate the same query. It always returns a complete decision, shaped as in [`schemas/decision.schema.json`](../schemas/decision.schema.json).

### 3. Enforce the decision

| Decision | Do |
|---|---|
| `allow: true` | Forward the call. |
| `require_approval: true` | Hold the call and ask a human. Forward it only if they approve. `allow` is false here, so code that checks only `allow` blocks it, which is the safe failure. |
| `allow: false` with `deny` entries | Refuse the call. Return the `message` values to the agent if you want it to adjust, and log the `code` values. |
| no answer, an error or no `result` | Refuse the call. |

Attach `obligations.audit_tags` to your audit record for the call.

### 4. Cover what the policies cannot see

These packs authorize `tools/call` only. Some servers also expose data as MCP resources; the filesystem server, for example, serves any file in its allowed directories through `resources/read`. Block or separately authorize `resources/read` and other methods for those servers, or the tool rules can be bypassed.

### 5. Test it

Run each fixture under `packs/*/fixtures/` through your adapter, then compare the outcome with the expectation in the file name. `scripts/e2e.sh` does this against a plain OPA server and is a reasonable template.
