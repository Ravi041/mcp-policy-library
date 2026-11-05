# Input contract

Every decision is computed from one JSON document describing one MCP `tools/call`. The authoritative definition is [`schemas/input.schema.json`](../schemas/input.schema.json), written in JSON Schema draft-07 because that is the draft OPA's `json.match_schema` validates. This page explains the fields.

The contract is engine-neutral, so a future Cedar version of the packs can read the same document.

## Example

```json
{
  "version": "1.0",
  "request_id": "req-push-to-main",
  "timestamp": "2026-11-05T12:00:00Z",
  "principal": {"id": "alice@example.com", "type": "user", "roles": ["developer"]},
  "agent": {"id": "agent-1", "name": "example-agent"},
  "server": {"name": "github", "transport": "stdio"},
  "tool": {"name": "push_files"},
  "arguments": {"owner": "acme", "repo": "web", "branch": "main", "message": "m", "files": [{"path": "a", "content": "x"}]},
  "context": {"environment": "production"}
}
```

## Fields

| Field | Required | Set by | Meaning |
|---|---|---|---|
| `version` | yes | integration | Schema version, `1.x`. Any other major version is denied with `main.unsupported_input_version`. |
| `request_id` | no | integration | Correlation ID for logs. |
| `timestamp` | no | integration | RFC 3339 time the call was received. The only clock policies read, so decisions are deterministic. Time-based rules deny when it is missing. |
| `principal.id`, `principal.type` | yes | integration, from authenticated identity | The human (`user`) or service (`service`) on whose behalf the call runs. |
| `principal.roles`, `groups`, `tenant`, `claims` | no | integration | Further identity attributes, for your own rules. The v0.1 packs do not read them. |
| `agent.id`, `agent.name` | no | integration | The calling agent. |
| `server.name` | yes | integration configuration | Selects the pack. Never let the agent influence it. |
| `server.version`, `transport` | no | integration | Server details. |
| `server.labels` | no | integration | Free-form string labels. |
| `tool.name` | yes | the request | The tool being called. |
| `tool.annotations` | no | the server's `tools/list` | Self-reported hints. They can cause a deny but never grant access. |
| `arguments` | yes, may be empty | the agent | Tool arguments exactly as sent. Untrusted. |
| `context.environment`, `session` | no | integration | Deployment and session context, such as call counts. |
| `context.labels` | no | integration | Free-form string labels. |

## Rules for integrations

- **Unknown fields are rejected** everywhere except `arguments`, `tool.annotations`, `principal.claims`, `context.session` and the two `labels` objects. This keeps vendor fields out of the contract. Put integration-specific values in `labels`.
- **Malformed input is denied at runtime.** Required fields are also checked by the policy itself. Input without `version`, `principal.id`, `server.name`, `tool.name` or an object `arguments` is denied with `main.invalid_input`, even if a pack would allow it.
- **Changes are versioned.** Adding an optional field is a minor version change. Removing or changing a field is a major version change, which current policies deny.
