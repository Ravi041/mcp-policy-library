# Writing a pack

A pack is the policy for one MCP server. This guide walks through adding one. [`CLAUDE.md`](../CLAUDE.md) has the same checklist in short form.

## 1. Verify the server first

Find the server's official source or README at a release tag. Record every tool name, and every argument your rules will read, with its type and whether it is required. Note the version; it goes in your README's `Verified against:` line.

If you cannot verify a tool, leave it out. A pack only allows tools it names, so a missing tool is denied rather than allowed by mistake.

## 2. Create the files

```
policies/mcp/packs/<pack>/policy.rego         package mcp.packs.<pack>
policies/mcp/packs/<pack>/policy_test.rego    package mcp.packs.<pack>_test
packs/<pack>/README.md
packs/<pack>/data.example.json
packs/<pack>/fixtures/*.json
```

Keep JSON out of `policies/`. OPA merges every JSON file it loads from a directory into `data`, so a fixture there breaks `opa test policies/`.

## 3. Write the tests first

Cover, at least:

- **Allow cases** for each tool group.
- **Deny cases** for each deny code.
- **Missing fields:** empty `arguments`, each required argument missing.
- **Wrong types:** a number, `null` or a list where a string is expected.
- **No config:** with no `data.mcp_config.<pack>`, nothing beyond your documented defaults is allowed.
- **Mistyped config:** a string where a list is expected must not grant access.
- **Annotations never grant:** `readOnlyHint: true` on a denied call does not allow it.

Run `make test` and watch them fail.

## 4. Write the policy

A pack exports these rules:

| Rule | Type | Required |
|---|---|---|
| `allow` | boolean, `default allow := false` | yes |
| `deny` | set of `lib.deny_reason(pack_name, "<reason>", message)` | yes |
| `require_approval` | boolean, `default require_approval := false` | yes |
| `audit_tags` | set of strings | no |

Rules for safe Rego:

- **Read config with defaults.** Use `default config := {}` and `config := data.mcp_config.<pack>`, then `default x := []` for each list.
- **Open flags only on a literal `true`.** Use `lib.flag_enabled(config, "<flag>")`.
- **Make `allow` positive.** It must check what is present, not the absence of a deny alone.
- **Write deny rules as `not <positive check>`,** so missing input denies.
- **Never negate a direct read of input.** `not is_string(input.arguments.x)` is undefined, not true, when `x` is missing, so it fails open. Wrap it: `x_is_string if is_string(input.arguments.x)`, then `not x_is_string`. `make qa` rejects the direct form.
- **Keep messages defined.** Use a defaulted value such as `default tool_name := "<missing>"` inside `sprintf`. An undefined value makes the whole reason vanish.
- **Leave annotations alone.** Only the baseline pack reads them.

## 5. Add fixtures

Fixtures are complete inputs, valid against the input schema. Their file names state the expected outcome:

| File name | Expected |
|---|---|
| `allow_<description>.json` | allowed |
| `approve_<description>.json` | held for approval |
| `deny_<code>[--<description>].json` | denied, with `<code>` among the reasons |

`make fixtures` evaluates them with every pack's example config loaded, and `make e2e` sends them to a real OPA server.

## 6. Document it

The pack README needs:

- the `Verified against:` line
- every deny code; `make qa` fails if a code is missing
- every config key, with its type and default
- the limitations

## 7. Wire it in

- Add the pack name to `routable_packs` in `policies/mcp/main/main.rego`.
- Add a row to the pack table in the root `README.md`.
- If the server marks tools as destructive, add them to `destructive_allowlist` in `packs/baseline/data.example.json`.

Then run `make ci`.
