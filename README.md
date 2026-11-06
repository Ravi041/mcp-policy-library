# mcp-policy-library

Tested OPA/Rego policy packs that decide whether an AI agent may make a given MCP tool call.

AI agents act by calling tools on MCP (Model Context Protocol) servers: they open pull requests, write files and run SQL. Whether a call should run is an authorization decision. It should not depend on the model choosing to behave, and it should not be buried in one gateway's code. This library keeps that decision as policy-as-code: reviewed, tested, versioned and loadable by any MCP gateway, proxy, control plane or plain OPA sidecar.

It is policy content only, not an engine, proxy or gateway. Pair it with whatever already sits between your agents and their MCP servers.

```
agent --tools/call--> gateway / proxy / control plane --input--> OPA --decision--> gateway --> MCP server
                          (your integration)          (this library)
```

## Contents

- [Quickstart](#quickstart)
- [How it works](#how-it-works)
- [Available packs](#available-packs)
- [Configuring a pack](#configuring-a-pack)
- [Integrations](#integrations)
- [Testing](#testing)
- [Repository layout](#repository-layout)
- [Writing a pack](#writing-a-pack)
- [Contributing, security and license](#contributing-security-and-license)

## Quickstart

You need `make`, `curl` and a POSIX shell on macOS or Linux. `make tools` downloads the pinned OPA and Regal binaries into `.bin/` and checks their SHA-256 checksums.

```sh
git clone https://github.com/Ravi041/mcp-policy-library.git
cd mcp-policy-library
make tools
export PATH="$PWD/.bin:$PATH"
```

An agent tries to push straight to `main`:

```sh
opa eval --format=pretty \
  --data policies/ \
  --data packs/github/data.example.json \
  --input examples/github-push-to-main-denied/input.json \
  'data.mcp.main.decision'
```

```json
{
  "allow": false,
  "deny": [
    {
      "code": "github.protected_branch",
      "message": "branch \"main\" is protected; open a pull request instead",
      "pack": "github"
    }
  ],
  "obligations": {
    "audit_tags": [
      "github:write",
      "pack:github"
    ]
  },
  "policy_version": "0.1.0",
  "require_approval": false
}
```

Swap in `examples/github-pull-request-allowed/input.json` and the same agent may open a pull request into `main`. The other directories under [`examples/`](examples/) show a merge held for human approval, filesystem traversal and a Postgres transaction escape.

To serve decisions over HTTP, as an integration would:

```sh
make bundle config-bundle
opa run --server --addr 127.0.0.1:8181 \
  --bundle dist/mcp-policy-library.tar.gz --bundle dist/config.tar.gz &

curl -s -H 'Content-Type: application/json' \
  --data "{\"input\": $(cat examples/github-pull-request-allowed/input.json)}" \
  http://127.0.0.1:8181/v1/data/mcp/main/decision
```

```json
{"result":{"allow":true,"deny":[],"obligations":{"audit_tags":["github:write","pack:github"]},"policy_version":"0.1.0","require_approval":false}}
```

## How it works

```
+--------------------+    normalized input    +-------------------------------+
| gateway, proxy or  | ---------------------> | OPA                           |
| control plane      |    (input.schema)      |  data.mcp.main.decision       |
| (your integration) | <--------------------- |   1. validate input           |
+--------------------+       decision         |   2. baseline pack (always)   |
          |                (decision.schema)  |   3. pack for server.name     |
          | only if allow                     |   4. merge: deny wins         |
          v                                   +-------------------------------+
+--------------------+                                     ^
| MCP server         |                                     | data.mcp_config
+--------------------+                           (your configuration)
```

1. **Normalize.** Your integration describes the tool call in a fixed shape: who is calling, which server, which tool, with which arguments. See the [input contract](docs/input-contract.md) and [`schemas/input.schema.json`](schemas/input.schema.json). Policies read nothing else, so they work with any gateway.
2. **Query.** Your integration asks OPA for `data.mcp.main.decision`, the one entrypoint for every integration.
3. **Decide.** The router validates the input, applies the `baseline` pack to every call, applies the pack matching `server.name`, and merges the results. A call is allowed only if a rule allows it and nothing denies it. A server with no pack gets baseline only, which denies by default.
4. **Enforce.** The decision follows [`schemas/decision.schema.json`](schemas/decision.schema.json):

| Field | Meaning |
|---|---|
| `allow` | Run the call only if this is `true`. |
| `deny` | Every reason for a refusal, each with a stable `code` such as `github.protected_branch`, a `message` and the `pack`. A refusal always has at least one reason. |
| `require_approval` | Hold the call for a human. `allow` stays `false`, so an integration that ignores this field blocks the call instead of running it. |
| `obligations.audit_tags` | Tags for your audit log. |
| `policy_version` | The library version that decided. |

The [decision model](docs/decision-model.md) has the full rules.

Design principles the code and the QA gates enforce:

- **Tool-neutral.** Policies never reference a gateway or vendor.
- **Default deny.** Deny always wins.
- **Configurable through data, not Rego edits.**
- **Explainable.** Every deny has a stable code.
- **Annotations cannot grant.** MCP tool annotations such as `readOnlyHint` are self-reported by servers, so they can cause a deny but never allow a call.

## Available packs

| Pack | Server | What it controls | Verified against |
|---|---|---|---|
| [baseline](packs/baseline/README.md) | every call | Server allowlist, tools marked destructive, business-hours window, fallback allowlist for servers with no pack | not applicable |
| [filesystem](packs/filesystem/README.md) | MCP reference filesystem server | Separate read and write directory allowlists, traversal and encoded-path protection, deny globs such as `**/.env` | `@modelcontextprotocol/server-filesystem` 2.2.0 |
| [github](packs/github/README.md) | GitHub MCP server | Repository and organization allowlist; protected branches and workflow files; no repository deletion or administration; merges, workflow runs, Copilot, secret alerts, global search and agent approvals off unless configured | `github/github-mcp-server` v2.1.0 |
| [postgres](packs/postgres/README.md) | postgres-mcp, and the archived reference server | Read-only by default; DDL, writes, multiple statements, `EXPLAIN ANALYZE` and side-effect functions blocked; SQL it cannot read reliably refused | `crystaldba/postgres-mcp` v0.3.0, `@modelcontextprotocol/server-postgres` 0.6.2 |

Each pack README lists its tools, deny codes, configuration and limitations. Read the limitations: for example, SQL inspection in Rego is best-effort and is not a substitute for database permissions, and the filesystem server can serve files through MCP resources, which tool-call policy does not see.

Tool names and arguments were checked against each server's source at the version shown. A tool a pack does not name is denied, so a newer server release cannot widen access by adding tools.

## Configuring a pack

Behavior is tuned through OPA data under `data.mcp_config.<pack>`, never by editing Rego. Each pack ships a `data.example.json`:

```json
{
  "mcp_config": {
    "github": {
      "allowed_repos": ["acme/web"],
      "protected_branches": ["main", "master", "release/*"],
      "allow_merge": true,
      "require_approval_tools": ["merge_pull_request"]
    }
  }
}
```

- **Missing config means the most restrictive behavior.** For example, no repository is allowed until `allowed_repos` or `allowed_orgs` is set.
- **Flags turn on only for a literal `true`.**
- **Router aliases** go in `data.mcp_config.main.server_aliases`, such as `{"gh-prod": "github"}`, and map your server names to packs.

Ship configuration as its own bundle, separate from the policy bundle. The policy bundle owns the `mcp` root and configuration owns `mcp_config`, so you can change configuration without touching the policy:

```sh
sh scripts/build-config-bundle.sh dist/config.tar.gz my-config.json
```

Every key is documented in its pack README.

## Integrations

| Integration | What it is |
|---|---|
| [Generic OPA sidecar](integrations/opa-sidecar/README.md) | OPA over HTTP, with a Docker Compose example pinned by image digest |
| [Kavrynt](integrations/kavrynt/README.md) | Documentation only, until Kavrynt's loading API is confirmed |
| [Write your own adapter](integrations/README.md) | How to build the input, query OPA and enforce the decision for any gateway |

Two rules apply to every integration:

- **Fail closed.** Treat an error, a timeout, a non-200 response or a missing `result` as a deny.
- **Cover what tool rules cannot see.** These packs authorize `tools/call` only, so block or separately authorize other MCP methods, such as `resources/read`, for servers that expose data through them.

Each tagged release attaches `mcp-policy-library.tar.gz`, an OPA bundle with root `mcp`, to its GitHub release. Load it alongside your own config bundle.

## Testing

Everything runs with only OPA and Regal. `make ci` runs every layer except the Docker test.

| Layer | Command | What it checks |
|---|---|---|
| Static | `make fmt-check check lint` | `opa fmt`, `opa check --strict` and Regal |
| Unit | `make test`, `make coverage` | Allow, deny and edge cases for every pack, and router invariants; at least 90% coverage |
| Contract | `make fixtures` | Every fixture and example is valid against the input schema, every decision is valid against the decision schema, and every outcome matches what the file name says |
| QA | `make qa` | The design principles hold: no vendor names in policies, only documented input fields, only baseline reads annotations, no fail-open negations, every pack complete and every deny code documented, actions pinned by SHA |
| End to end | `make e2e` | A real OPA server, loaded from the policy and config bundles, answers every fixture and example correctly over HTTP. With no config, nothing is allowed. Malformed requests fail closed. |
| End to end, Docker | `make e2e-docker` | The Docker Compose sidecar serves correct decisions |

Three GitHub Actions workflows run these on every pull request:

- **`ci`:** static, unit and contract tests, uploading the bundle as an artifact. On `v*` tags it attaches the bundle to the release.
- **`qa`:** the QA gates.
- **`e2e`:** the HTTP and Docker end-to-end tests.

[docs/testing.md](docs/testing.md) explains each layer, the fixture naming convention and how to run a single test.

| Tool | Version |
|---|---|
| OPA | v1.22.1 |
| Regal | v0.43.0 |

The policies use Rego v1 syntax and avoid template strings. They have been tested only with the OPA version above.

## Repository layout

```
policies/                      Rego only; the bundle root is mcp
  mcp/main/                    entrypoint and router: data.mcp.main.decision
  mcp/lib/                     shared helpers: paths, time windows, reasons
  mcp/packs/<pack>/            policy.rego and policy_test.rego
packs/<pack>/                  README, data.example.json, fixtures/
schemas/                       input and decision contracts (JSON Schema)
examples/<name>/               input.json and its exact decision.json
integrations/                  OPA sidecar, Kavrynt notes, adapter guide
scripts/                       tool install, fixtures, QA, end-to-end tests
docs/                          input contract, decision model, writing a pack, testing
```

Rego and JSON are kept in separate trees because OPA merges every JSON file it loads from a directory into `data`. Fixtures next to the policies would break `opa test policies/`.

## Writing a pack

See [docs/writing-a-pack.md](docs/writing-a-pack.md). In short:

1. Verify the server's tool names at a release tag.
2. Write the tests first.
3. Read all settings from `data.mcp_config.<pack>`.
4. Add fixtures and a README documenting every deny code.
5. Register the pack in the router and in the table above.

`make qa` checks most of this.

## Contributing, security and license

- Contributions: [CONTRIBUTING.md](CONTRIBUTING.md)
- Reporting a vulnerability: [SECURITY.md](SECURITY.md). Please do not open a public issue for security problems.
- License: [Apache-2.0](LICENSE)
