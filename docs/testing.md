# Testing

Six layers of tests run locally with `make` and in three GitHub Actions workflows. They need only OPA and Regal, which `make tools` installs at pinned versions into `.bin/` after checking their SHA-256 checksums against `scripts/tools.sha256`.

| Layer | Command | Workflow | What it proves |
|---|---|---|---|
| Static | `make fmt-check check lint` | `ci` | Rego is formatted, compiles under `opa check --strict`, and passes Regal |
| Unit | `make test`, `make coverage` | `ci` | Each rule does what its tests say; coverage is at least 90% |
| Contract | `make fixtures` | `ci` | Fixtures are valid inputs, decisions are valid outputs, outcomes match file names, examples match exactly |
| Replay | `make replay` | `ci` | Recorded tool calls still get the outcome they got when they were recorded |
| QA | `make qa` | `qa` | The design principles hold across the repository |
| End to end | `make e2e`, `make e2e-docker` | `e2e` | A real OPA server, loaded the way a deployment loads it, answers correctly over HTTP |

`make ci` runs every layer except the Docker test.

## Unit tests

Tests sit next to the code they test, as `*_test.rego` in packages ending in `_test`. `make test` also runs the agentgateway adapter's tests, in `integrations/agentgateway/policy/`, against the library. Each pack's tests cover allow cases, deny cases and edge cases: missing fields, wrong types, empty arguments, no config and mistyped config. The router's tests mock packs with `with data.mcp.packs.<pack> as {...}`, and check these invariants for every outcome:

- A refusal always carries at least one reason.
- An allowed call never carries reasons.
- An approval request never comes with `allow: true` or with reasons.

`make coverage` fails below 90% and lists every file under 100%.

## Contract tests

`scripts/check-fixtures.sh` works through `packs/*/fixtures/*.json` and `examples/*/`. For each, it:

1. Validates the input against `schemas/input.schema.json` with OPA's `json.match_schema`.
2. Evaluates `data.mcp.main.decision` with every pack's `data.example.json` loaded.
3. Validates the decision against `schemas/decision.schema.json`.
4. Checks the outcome. Fixtures are named `allow_*`, `approve_*` or `deny_<code>[--<description>]`. Examples must match their `decision.json` exactly.

## Replaying real traces

Fixtures are written by hand. A trace is what your agents really sent. `scripts/replay.sh` takes an OPA decision log, evaluates every recorded tool call again with the policies in this checkout, and compares each outcome with the one that was recorded. Use it before you upgrade the library or change your config, to see which real calls would be decided differently.

```sh
make replay TRACE=/var/log/opa/decisions.log CONFIG=/etc/mcp/config.json
```

With no arguments, `make replay` checks the sample in `examples/trace/` against every pack's example config, which is what CI runs.

### Recording a trace

Turn on decision logs where OPA runs, for example with `--set decision_logs.console=true`, and keep the output. Each record holds the input and the result, so the log is its own expected output. Two kinds of record are replayed, and anything else is skipped:

| Logged query | What the record holds |
|---|---|
| `data.mcp.main.decision` | The library input and the decision |
| The agentgateway adapter's `response` | The gateway's check. The adapter is run again to build the library input, so the replay covers the adapter too. |

A decision log does not record the config. Pass the config that was live when the trace was recorded, or every call will look as if it moved.

Traces hold tool arguments: SQL, file contents, repository names. Keep them out of the repository unless they are synthetic. A decision-log mask policy that removes arguments also changes what the packs see, so a masked trace cannot be replayed faithfully. The report itself prints only the decision ID, server, tool and deny codes.

### What fails

| Report line | Meaning | Fails |
|---|---|---|
| `LOOSENED` | The call was refused or held for approval, and is now more open | yes: a security regression |
| `TIGHTENED` | The call was allowed, and is now refused or held for approval | yes: a usability regression |
| `CONTRACT` | A call that was allowed or held has an input that breaks `schemas/input.schema.json`, or a decision breaks the decision schema | yes: the integration has drifted from the contract |
| `REASONS` | The call is still refused, with different deny codes | no |

A trace with no replayable record fails too, so an empty or misrouted log cannot pass by accident.

Both directions fail on purpose. A security fix should refuse the attack it targets without refusing the calls your agents make every day, and the replay is how you check the second half: the hardening release must leave your recorded allows alone.

Some moves are intended. A fix that refuses a call which should never have run will show as `TIGHTENED`; a corrected false positive will show as `LOOSENED`. Review each one, then list its decision ID in a file, one per line, and pass it:

```sh
REPLAY_ACCEPT=accepted.txt make replay TRACE=decisions.log CONFIG=config.json
```

Accepted moves are still printed, marked `accepted`. Any move not in the file still fails.

To test a built bundle, such as a release candidate, set `REPLAY_POLICY=dist/mcp-policy-library.tar.gz`.

## QA gates

`scripts/qa.sh` checks what formatting, lint and tests cannot:

| Gate | Principle |
|---|---|
| Schemas are valid draft-07 | contracts |
| No gateway or vendor name appears in `policies/` | tool-neutral |
| Policies read only top-level input fields that the schema documents | tool-neutral |
| No `.cedar` files and no `future.keywords` imports | Rego v1 only |
| Only the baseline pack reads `annotations` | don't trust self-reported metadata |
| No `not f(input.x)` or `not input.x in y`, which fail open when the field is missing | default deny |
| Every pack has its policy, tests, README with `Verified against:`, example data and both allow and deny fixtures | pack completeness |
| Every pack except baseline is routable and listed in the root README | pack completeness |
| Every deny code is documented in its pack README or in `docs/decision-model.md` | explainable decisions |
| Every workflow action is pinned to a full commit SHA | supply chain |
| The README is plain ASCII | documentation |
| Example decisions carry the current `policy_version`, and a release tag matches it | releases |

## End-to-end tests

`scripts/e2e.sh` builds the policy bundle and a separate config bundle, starts two OPA servers, and runs six scenarios over HTTP.

The first server has both bundles loaded:

1. **Fixtures.** Every fixture gets its expected outcome, and every decision is schema-valid.
2. **Examples.** Every example returns exactly its `decision.json`.
3. **Empty input.** An empty input and a request with no input both get a complete decision with `main.invalid_input`.
4. **Malformed JSON.** Malformed JSON gets HTTP 400.
5. **Wrong path.** A wrong query path returns no `result`.

The second server has only the policy bundle loaded:

6. **No config.** Every `allow_*` and `approve_*` fixture is refused, showing that configuration can only open access. The only exceptions are fixtures named `allow_postgres_default_*`, because read-only SQL is the postgres pack's documented default.

`scripts/e2e-docker.sh` starts `integrations/opa-sidecar/docker-compose.yml` from the built bundles and checks one allowed and one denied call. It runs in the `e2e` workflow and needs a running Docker daemon locally.

## Gateway walkthrough

`integrations/agentgateway/try.sh` runs the library behind agentgateway, with real MCP servers, and makes 29 checks. They cover identity, every pack, side effects and failing closed when OPA is down. It downloads a gateway and MCP servers, so it is not part of CI. [Try it with an MCP gateway](try-it-with-gateways.md) is the runbook.

## Running one thing

```sh
export PATH="$PWD/.bin:$PATH"
opa test policies/ --run 'test_traversal'     # tests whose names match
opa test policies/mcp/packs/github/ policies/mcp/lib/ policies/mcp/main/
opa eval --data policies/ --data packs/github/data.example.json \
  --input packs/github/fixtures/deny_github.protected_branch--push_to_main.json \
  --format=pretty 'data.mcp.main.decision'
```

## CI workflows

| Workflow | Triggers | Jobs |
|---|---|---|
| `.github/workflows/ci.yml` | pull requests, pushes to `main`, `v*` tags | `test`, which includes the replay and uploads the bundle as the `opa-bundle` artifact; `release` on tags, which runs QA, checks the tag against `policy_version` and attaches the bundle to the GitHub release |
| `.github/workflows/qa.yml` | pull requests, pushes to `main` | `qa` |
| `.github/workflows/e2e.yml` | pull requests, pushes to `main` | `server`, the HTTP tests; `sidecar`, the Docker Compose test |

Every workflow has read-only permissions except the release job, which can write repository contents. Every action is pinned by SHA.
