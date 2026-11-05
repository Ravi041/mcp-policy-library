# Decision model

## The entrypoint

`data.mcp.main.decision` is the only query integrations need. It always returns a complete decision, even for empty or malformed input. Its shape is defined in [`schemas/decision.schema.json`](../schemas/decision.schema.json).

## How a decision is made

```
input
  |
  +-- main: validate the input --------------------------+
  |                                                      |
  +-- baseline pack: global denies, every call ----------+--> deny reasons
  |                                                      |
  +-- routed pack: allow, deny, require_approval --------+
        chosen by server.name, or by
        data.mcp_config.main.server_aliases
```

1. **Route.** `server.name`, or its alias, picks one pack from `routable_packs` in `policies/mcp/main/main.rego`. `baseline` is never a route, and a server with no pack is unrouted.
2. **Collect denies.** Input errors, every baseline deny and every routed pack deny are merged.
3. **Find an allow.** For a routed server, only that pack's `allow` counts. For an unrouted server, only baseline's `allow` counts, which by default allows nothing.
4. **Decide.**

| Situation | `allow` | `require_approval` | `deny` |
|---|---|---|---|
| any deny reason | `false` | `false` | the reasons |
| no deny, no allow rule | `false` | `false` | `main.no_allow_rule` |
| allowed, pack asks for approval | `false` | `true` | empty |
| allowed | `true` | `false` | empty |

Deny always wins: an approval request cannot override a deny, and a refusal always carries at least one reason. The unit tests in `policies/mcp/main/main_test.rego` check these invariants.

## Why approval leaves `allow` false

An integration that does not understand `require_approval` will look only at `allow`. With `allow: false`, it blocks the call, which is safe. If approval returned `allow: true`, the same integration would run the call without asking anyone.

## Router and input codes

| Code | Meaning |
|---|---|
| `main.invalid_input` | A required field is missing or has the wrong type: `version`, `principal.id`, `server.name`, `tool.name` or `arguments` |
| `main.unsupported_input_version` | `version` is not `1.x` |
| `main.no_allow_rule` | Nothing denied the call, but no rule allowed it either. This is default deny. |

Each pack documents its own codes in `packs/<pack>/README.md`.

## Codes and messages

- **`code`** is stable within a major version and is safe to match on: `<pack>.<reason>`, lower case.
- **`message`** is for people. It may change in any release.
- **`pack`** names the pack that produced the reason.

## Obligations

`obligations.audit_tags` always includes `pack:<name>` for the pack that handled the call (`pack:baseline` for unrouted servers), plus tags from that pack such as `github:write` or `postgres:read`. Integrations should attach them to their audit record.

## `policy_version`

The library version that produced the decision. A release tag must match it; the release workflow checks this.
