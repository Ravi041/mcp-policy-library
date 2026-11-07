# baseline pack

Runs on every tool call, whichever server it targets. It adds global guardrails to every other pack, and it is the only pack that applies to a server with no pack of its own.

Verified against: not applicable. This pack names no server tools; it reads only the normalized input.

## Rules

| Code | Denies when |
|---|---|
| `baseline.server_not_allowed` | `allowed_servers` is configured and `server.name` is not in it |
| `baseline.destructive_tool` | `tool.annotations.destructiveHint` is present and not `false`, and the tool is not allowlisted for that server |
| `baseline.invalid_timestamp` | `business_hours` is configured and `timestamp` is missing or invalid |
| `baseline.outside_business_hours` | `business_hours` is configured and the call falls outside it, or the window itself is invalid |
| `baseline.invalid_config` | a key in `data.mcp_config.baseline` has the wrong type, such as a string where a list belongs, or that config is not an object. Every call to any server is refused until it is fixed, because a malformed deny list would otherwise switch its check off. |

The `allow` rule is used only when a server has no pack. For a server with a pack, listing a tool under `allowed_tools` has no effect.

## Configuration

Config lives under `data.mcp_config.baseline`. Every key is optional.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `allowed_servers` | list of strings | no restriction | Raw `server.name` values that may be called. An empty list denies every server. |
| `destructive_allowlist` | object of server name to tool list | none | Tools allowed despite `destructiveHint`. Keyed by raw `server.name`, not by pack. |
| `allowed_tools` | object of server name to tool list | none | Exact tools allowed on servers with no pack. There is no wildcard. |
| `business_hours` | object | no window | Same-day window with `timezone`, `days`, `start` and `end`. |

`data.mcp_config.main.server_aliases` is also shown in this pack's example because it applies to the router. It maps a raw `server.name` to a pack, for example `{"gh-prod": "github"}`.

A window looks like this:

```json
{
  "timezone": "Asia/Kolkata",
  "days": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
  "start": "09:00",
  "end": "18:00"
}
```

`start` is inclusive and `end` is exclusive. A window whose `start` is after its `end` never matches, so overnight windows are not supported and deny every call.

## Things to know

- **Annotations can only restrict.** `readOnlyHint: true` never allows anything, and `destructiveHint: false` only means this rule does not fire. A pack's own rules still have to allow the call.
- **A missing hint does not count as destructive.** The MCP specification treats an absent `destructiveHint` as true for tools that are not read-only. This pack fires only on an explicit hint, because denying every unannotated tool would make the rule useless. Packs and `allowed_tools` are positive allowlists, so an unannotated tool is still denied unless a rule allows it.
- **This rule affects filesystem writes.** The filesystem server marks `write_file`, `edit_file` and `move_file` as destructive, so they need an entry in `destructive_allowlist` as well as in the filesystem pack's own config. The example config includes them.
- **The clock comes from the input.** Rules read `timestamp`, which the integration sets. Whoever controls that field controls the time check, so it must come from the integration and never from the agent.
