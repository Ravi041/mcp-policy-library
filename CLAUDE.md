# mcp-policy-library

A library of tested OPA/Rego policy packs that authorize AI agent tool calls made through MCP (Model Context Protocol). It is policy content that any MCP gateway, proxy, control plane or plain OPA sidecar can load; it is not an engine, proxy or gateway.

## Design principles

1. **Tool-neutral.** No policy references a specific gateway, vendor or product. Policies read only the normalized input in `schemas/`. Gateway-specific mapping lives in `integrations/`, never in `policies/`.
2. **Engine-ready for later.** Rego (OPA 1.x, Rego v1 syntax) is the only engine now. Keep schemas engine-neutral so a Cedar version can be added later.
3. **Default deny.** A call is allowed only if a rule allows it and no rule denies it. Deny always wins.
4. **Configurable through data.** Allowed repos, paths, schemas and hours come from `data.mcp_config.<pack>`, never from editing Rego.
5. **Explainable decisions.** Every deny has a stable code (`<pack>.<reason>`) and a human-readable message.
6. **Don't trust self-reported metadata.** MCP tool annotations may inform a deny but must never be the only reason something is allowed.
7. **Verify, don't guess.** Check real tool names and argument shapes in the server's official source or README at a release tag, and record that version in the pack README. If you cannot verify, stop and say so.

## Contracts

- `schemas/input.schema.json`: the normalized tool call (`version`, `request_id`, `timestamp`, `principal`, `agent`, `server`, `tool`, `arguments`, `context`). Draft-07, because that is what `json.match_schema` validates.
- `schemas/decision.schema.json`: `allow`, `deny` (`{code, message, pack}`), `require_approval`, `obligations`, `policy_version`.
- Entrypoint: `data.mcp.main.decision`. It is the one query for every integration and always returns a complete decision.
- `main` routes `input.server.name` (or an alias from `data.mcp_config.main.server_aliases`) to a pack in `routable_packs`, applies `baseline` to every call and merges results. Unknown servers get baseline only.
- Approval returns `allow: false, require_approval: true, deny: []`, so an integration that ignores the flag fails closed.

## Layout

```
policies/                    Rego only, so plain OPA commands work
  .manifest                  bundle root: mcp
  mcp/lib/                   pure helpers (package mcp.lib)
  mcp/main/                  entrypoint and router (package mcp.main)
  mcp/packs/<pack>/          policy.rego, policy_test.rego
packs/<pack>/                README.md, data.example.json, fixtures/
schemas/                     input and decision contracts
scripts/                     tool install, fixture check, QA, end-to-end tests
  replay/                    trace replay Rego (package mcp_replay), covered by make test
integrations/                adapters and deployment examples, gateway specifics go here
  agentgateway/policy/       adapter Rego (package mcp_adapters.agentgateway), covered by make test
examples/<name>/             input.json and decision.json, end to end
examples/trace/              a sample decision log for make replay
docs/                        input contract, decision model, writing a pack, testing
```

Never put JSON or YAML under `policies/`. OPA merges every such file it finds by directory, which breaks `opa test policies/` with a merge error. The only exception is the bundle `.manifest`.

## Commands

Install the pinned tools once with `make tools`. They land in `.bin/`, which the Makefile puts on `PATH`. To call `opa` directly, run `export PATH="$PWD/.bin:$PATH"`.

| Task | Command |
|---|---|
| Format | `make fmt` (check only: `make fmt-check`) |
| Compile strictly | `make check` |
| Lint | `make lint` |
| Unit tests | `make test` |
| Coverage, fails below 90% | `make coverage` |
| Fixtures and examples | `make fixtures` |
| Replay a recorded decision log | `make replay TRACE=<log> CONFIG=<data.json>` |
| QA gates | `make qa` |
| Build the bundle | `make bundle` |
| End-to-end over HTTP | `make e2e` |
| End-to-end in Docker | `make e2e-docker` |
| All except Docker | `make ci` |

## Adding a pack

1. Verify tool names and argument shapes at a release tag of the server's official source. Record the version in the pack README's `Verified against:` line.
2. Write `policies/mcp/packs/<pack>/policy_test.rego` first and watch it fail.
3. Write `policy.rego` in package `mcp.packs.<pack>`, exporting `allow`, `deny` and `require_approval`, and optionally `audit_tags`.
4. Read all settings from `data.mcp_config.<pack>` with safe defaults. Add `packs/<pack>/data.example.json` holding only the `mcp_config` key.
5. Add `packs/<pack>/fixtures/`, named `allow_*`, `approve_*` or `deny_<code>[--<description>]`. They must be valid against the input schema.
6. Test allow cases, deny cases and edge cases: missing fields, unexpected types, empty arguments.
7. Write `packs/<pack>/README.md`, documenting every deny code and config key.
8. Add the pack to `routable_packs` in `policies/mcp/main/main.rego` and to the root README's pack table.
9. Run `make ci`.

## Writing Rego safely

- A rule that reads a missing field does not fire. Write deny rules as `not <positive check>` so missing and malformed input denies.
- `not is_string(input.x)` and `not input.x in y` are undefined when the field is missing, not true, so they fail open. Wrap the read in a helper rule (`x_is_string if is_string(input.x)`, then `not x_is_string`) or assign a defaulted value first. `make qa` rejects the direct form.
- An undefined value inside `sprintf` makes the whole reason undefined, and the deny vanishes. Use a defaulted value such as `tool_name` in messages.
- Builtin errors evaluate as undefined, so the same rule applies to wrong types.
- Only a literal `true` opens a config flag; use `lib.flag_enabled`.

In scripts, `opa eval --fail 'a == b'` exits 0 when the comparison is false, because `false` is a defined result. Use unification, `a = b`, or a query of several expressions.

## Don'ts

- No gateway-specific fields in policies. `labels` is the only place for integration-specific values.
- No Cedar yet.
- No allow based only on annotations.
- No unverified tool names.
- No dependency beyond OPA and Regal without asking the maintainer, including new CI actions from outside the `actions/` organization.
- No integration code that depends on Kavrynt's actual API until the maintainer confirms it. `integrations/kavrynt/` is docs only.
