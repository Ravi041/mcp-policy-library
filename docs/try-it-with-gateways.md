# Try it with an MCP gateway

This runbook puts the policy library in front of real MCP servers, behind a real MCP gateway, and shows what an agent gets back when a call is allowed or refused. It takes about ten minutes the first time, mostly for downloads.

The gateway is [agentgateway](https://agentgateway.dev). The MCP servers are:

- the reference filesystem server;
- GitHub's MCP server, with a placeholder token;
- `postgres-mcp`, against a throwaway Postgres in Docker;
- the reference `everything` server, which the configuration does not list.

[What was verified](#what-was-verified) lists the results of the last run.

```
MCP client --Bearer JWT--> agentgateway :3000 --ext_authz--> OPA-Envoy :9191
  (curl,                    /filesystem/mcp                   policy bundle  (mcp)
   MCP Inspector)           /github/mcp                       adapter        (mcp_adapters/agentgateway)
                            /postgres/mcp                     configuration  (mcp_config)
                            /everything/mcp
                                 |
                                 v  only if allowed
                            MCP servers (stdio)
```

## 1. Prerequisites

| Need | For | Check |
|---|---|---|
| macOS on Apple silicon, or Linux on amd64 or arm64 | agentgateway publishes builds for these | `uname -sm` |
| `make`, `curl`, `openssl`, `xxd` | install, dev tokens, the curl client | `openssl version` |
| Node.js and `npx` | the filesystem and `everything` servers | `npx --version` |
| Docker, running | the Postgres part. Optional: it is skipped without Docker. | `docker info` |

Ports 3000, 8181, 8182, 9191 and 55432 must be free.

## 2. Install the tools

```sh
git clone https://github.com/Ravi041/mcp-policy-library.git
cd mcp-policy-library
make tools                                # OPA and Regal
sh integrations/agentgateway/install.sh   # agentgateway, OPA-Envoy, github-mcp-server
export PATH="$PWD/.bin:$PATH"
```

Both installers check every download against the SHA-256 checksums committed in the repository, then put the binaries in `.bin/`. Nothing is installed system-wide. To skip the GitHub server, run the second installer with `WITH_GITHUB=0`.

## 3. Get the policy bundle

Use the released bundle:

```sh
mkdir -p dist
gh release download v0.1.1 --repo Ravi041/mcp-policy-library -p mcp-policy-library.tar.gz -D dist
shasum -a 256 dist/mcp-policy-library.tar.gz
# cdfae94f8fd792e8a32af2afa0b4999ca554e6a1b5d551dcc9d0326b774ba563
gh attestation verify dist/mcp-policy-library.tar.gz --repo Ravi041/mcp-policy-library
```

Do not use v0.1.0. It has authorization bypasses that 0.1.1 fixes; see the [changelog](../CHANGELOG.md).

Or build one from your checkout with `make bundle`. Either way it lands at `dist/mcp-policy-library.tar.gz`, where the walkthrough looks for it. Set `BUNDLE=/path/to/bundle.tar.gz` to use another file.

## 4. Run everything once

```sh
sh integrations/agentgateway/try.sh
```

`try.sh` takes these steps:

1. Creates a scratch directory, `.try/agentgateway/`, which git ignores. It holds a sample workspace, a dev signing key, a token for `alice@example.com` and a configuration bundle.
2. Starts Postgres in Docker with a small `orders` table and two denied schemas, `secrets` and `hr-data`.
3. Starts OPA-Envoy with three bundles: the policy library, the agentgateway adapter and the configuration.
4. Starts agentgateway with one route per MCP server.
5. Makes real MCP calls through the gateway and checks every answer. Where a call would change something, it also checks the file or table.
6. Stops OPA mid-run to prove the gateway fails closed.
7. Stops everything.

Expected output:

```
Identity, enforced by the gateway before OPA is asked
  PASS  no token is rejected with HTTP 401
  PASS  a token from another key is rejected with HTTP 401
filesystem pack
  PASS  tools/list passes                                          allowed
  PASS  read a file in an allowed directory                        allowed
  PASS  read outside the allowed directories                       refused:adapter.denied,filesystem.path_not_allowed
  PASS  read a .env file                                           refused:adapter.denied,filesystem.path_denied
  PASS  climb out with ..                                          refused:adapter.denied,filesystem.path_traversal
  PASS  relative path                                              refused:adapter.denied,filesystem.path_not_absolute
  PASS  write inside the write directory                           allowed
  PASS    ...and the file exists
  PASS  write outside the write directory                          refused:adapter.denied,filesystem.path_not_allowed
  PASS    ...and the file is unchanged
  PASS  a tool the pack does not name                              refused:adapter.denied,filesystem.tool_not_supported
  PASS  resources/read, which tool rules cannot see                refused:adapter.method_not_allowed
baseline pack
  PASS  a server the configuration does not list                   refused:adapter.denied,baseline.server_not_allowed
github pack
  PASS  read in an allowed repo (reaches GitHub, fake token)       forwarded-failed
  PASS  read in another repo                                       refused:adapter.denied,github.repo_not_allowed
  PASS  push straight to main                                      refused:adapter.denied,github.protected_branch
  PASS  edit a workflow file                                       refused:adapter.denied,github.protected_path
  PASS  merge, which needs approval                                refused:adapter.approval_required
postgres pack
  PASS  SELECT                                                     allowed
  PASS  DELETE                                                     refused:adapter.denied,postgres.unbounded_write,postgres.write_not_allowed
  PASS  escape a read-only transaction                             refused:adapter.denied,postgres.multiple_statements
  PASS  read a file through a function                             refused:adapter.denied,postgres.blocked_function
  PASS  read a denied schema                                       refused:adapter.denied,postgres.denied_schema
  PASS  read a denied schema behind a comment                      refused:adapter.denied,postgres.denied_schema
  PASS  read a table named in a string                             refused:adapter.denied,postgres.blocked_function
  PASS  run SQL through dblink                                     refused:adapter.denied,postgres.blocked_function,postgres.blocked_function
  PASS  schedule SQL with pg_cron                                  refused:adapter.denied,postgres.blocked_function
  PASS  EXPLAIN ANALYZE, which runs the statement                  refused:adapter.denied,postgres.explain_analyze,postgres.write_not_allowed
  PASS  EXPLAIN with a quoted analyze option                       refused:adapter.denied,postgres.explain_analyze
  PASS    ...and every order is still there
Failure handling
  PASS  OPA is down: the call is refused, not forwarded            http:403
  PASS    ...and nothing was written

34 passed, 0 failed, 0 skipped
```

`try.sh` keeps an existing `$WORK/config/data.json`, so you can edit it. If you ran an older version, delete that file first, or the `hr-data` check fails against the old configuration.

The script exits non-zero if any check fails.

The outcome words mean:

| Word | Meaning |
|---|---|
| `allowed` | The policy allowed the call and the server answered. |
| `refused:<codes>` | The policy refused it. The codes are the adapter's code, then the library's deny codes. |
| `forwarded-failed` | The policy allowed it and the server reported an error. GitHub answers "Bad credentials" because the token is a placeholder, which proves the call reached GitHub. |
| `http:<status>` | The gateway refused the request before any MCP exchange. |

## 5. Explore by hand

Start the stack and leave it running:

```sh
sh integrations/agentgateway/try.sh up
TOKEN=$(cat .try/agentgateway/token)
WS=$PWD/.try/agentgateway/workspace
```

### With the curl client

```sh
mcp() { route=$1; shift; MCP_TOKEN=$TOKEN MCP_SESSION_FILE=.try/agentgateway/sessions/$route \
  sh integrations/agentgateway/mcp-client.sh "http://127.0.0.1:3000/$route/mcp" "$@"; }

mcp github initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"me","version":"0"}}'
mcp github notifications/initialized
mcp github tools/call '{"name":"push_files","arguments":{"owner":"octo-org","repo":"demo","branch":"main","message":"m","files":[{"path":"a.txt","content":"a"}]}}'
```

The agent receives:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "error": {
    "code": -32001,
    "message": "refused by policy: github.protected_branch: branch \"main\" is protected; open a pull request instead",
    "data": {
      "code": "adapter.denied",
      "decision": {
        "allow": false,
        "deny": [{"code": "github.protected_branch", "message": "branch \"main\" is protected; open a pull request instead", "pack": "github"}],
        "obligations": {"audit_tags": ["github:write", "pack:github"]},
        "policy_version": "0.1.1",
        "require_approval": false
      }
    }
  }
}
```

Try the same call with `"branch":"feature/x"` and the policy lets it through.

### With the MCP Inspector CLI

The Inspector is the MCP project's reference client, built on the official SDK:

```sh
npx -y @modelcontextprotocol/inspector@2.14.0 --cli http://127.0.0.1:3000/filesystem/mcp \
  --transport http --header "Authorization: Bearer $TOKEN" \
  --method tools/call --tool-name read_text_file --tool-arg path=$WS/secrets/keys.txt
```

```
{"error":{"code":"error","message":"refused by policy: filesystem.path_not_allowed: path \".../workspace/secrets/keys.txt\" is outside the configured read paths"}}
```

Use `path=$WS/projects/app/README.md` and it returns the file.

Any MCP client that speaks Streamable HTTP and can send an `Authorization` header can connect the same way. Only curl and the Inspector were tested.

### Change the configuration, not the policy

The configuration is in `.try/agentgateway/config/data.json`. `up` keeps your edits. Remove `"**/.env"` from `filesystem.deny_globs`, then restart:

```sh
sh integrations/agentgateway/try.sh down
sh integrations/agentgateway/try.sh up
```

Reading `$WS/projects/app/.env` is now allowed, and nothing in the policy changed. Each pack README lists every key. Delete `data.json` to go back to the default, which `try.sh check` expects.

### Read the decision log

Every decision is logged as one JSON line in `.try/agentgateway/opa.log`. The line holds the adapter's input, its result and timings:

```sh
grep '"decision_id"' .try/agentgateway/opa.log | tail -1
```

The log includes tool arguments, such as file contents and SQL. Mask them before you ship logs anywhere.

### Stop

```sh
sh integrations/agentgateway/try.sh down
```

## 6. What was verified

Run on 2026-11-06 on macOS, Apple silicon, with the v0.1.0 release bundle, and again on 2026-11-07 with the v0.1.1 release bundle. The second run repeated every `try.sh` scenario and the curl example in section 5. The MCP Inspector, configuration and latency results below are from the first run.

| Component | Version |
|---|---|
| mcp-policy-library | v0.1.1 release bundle, sha256 `cdfae94f...`; v0.1.0, sha256 `930f8945...`, for the first run |
| agentgateway | v1.7.0 |
| OPA-Envoy | v1.22.0-envoy |
| `@modelcontextprotocol/server-filesystem` | 2.2.0 |
| `github/github-mcp-server` | v2.1.0 |
| `crystaldba/postgres-mcp` | 0.3.0, run with `--access-mode=unrestricted` so that every refusal comes from the policy |
| `@modelcontextprotocol/server-everything` | 2.2.1 |
| Postgres | 17.11 |
| MCP Inspector | 2.14.0 |

Results:

- **Scenarios.** All 34 `try.sh` checks passed. With OPA stopped, the same run reports every check that expects a policy answer as `FAIL`, so the harness does detect failures. Run against a bundle built before the 0.1.1 security review, the four checks for the issues it fixed fail and the other 30 pass.
- **Refusals block.** Refused writes left no file behind, and the refused `DELETE` and `EXPLAIN ANALYZE` left all three rows in place.
- **Allowed calls really run.** The allowed filesystem write created its file. The allowed SELECT returned the seeded rows. The allowed GitHub read reached `api.github.com` and came back "401 Bad credentials".
- **Identity.** A missing token or a token signed by another key gets HTTP 401 from the gateway, before OPA is asked.
- **Failing closed.** With OPA down, agentgateway logged `ext_authz request failed ... Connection refused` and answered HTTP 403. Nothing was written.
- **Real client.** The MCP Inspector CLI showed the policy's refusal message as the tool error, and showed allowed results normally.
- **Configuration only.** Editing `data.json` and restarting changed a decision with no change to the policy.
- **Latency.** Over 30 consecutive tool calls, OPA's server-side handling (`timer_server_handler_ns`) took 1.01 ms at p50, 1.82 ms at p90 and 6.44 ms at most. That includes building the input, evaluating the library and building the response.

The adapter also has 26 unit tests, which run with `make test`.

## 7. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `missing agentgateway` or `missing opa-envoy` | Run `sh integrations/agentgateway/install.sh` and `export PATH="$PWD/.bin:$PATH"`. |
| `no policy bundle at dist/...` | Do step 3. |
| `timed out waiting for agentgateway` | A port is in use: `lsof -nP -iTCP:3000 -sTCP:LISTEN`. Look in `.try/agentgateway/agentgateway.log`. |
| HTTP 401 on every call | The token lasts one hour. `try.sh up` writes a new one; reload `TOKEN`. |
| The first filesystem or `everything` call is slow | `npx` is downloading the server. Later runs use its cache. |
| `SKIP postgres pack` | Docker isn't running. Start it, then run `try.sh` again. The first run pulls two images. |
| `npm warn EBADENGINE` from the Inspector | Your Node.js is older than the Inspector asks for. The CLI still worked on Node 26.7. |

## Other gateways

These were examined but not tested. They are recorded here so the next adapter starts from facts.

- **Docker MCP Gateway** (v0.44.3). The hook is `docker mcp gateway run --interceptor before:exec:<command>`. It runs a command on each `tools/call`, with the request as JSON on stdin. Non-empty output replaces the result, so the tool never runs; a non-zero exit fails the call.
  - The stdin format is undocumented, and the server name may not be in it.
  - Servers must be container images listed in a catalog under `~/.docker/mcp/catalogs/`.
  - An adapter would be a small script that maps stdin to the input and calls OPA's REST API.
- **IBM ContextForge** (1.1.0). Its external OPA plugin queries `<base>/<policy>/allow`, or an endpoint name containing the hook name, such as `allow_tool_pre_invoke`. It accepts a boolean or an object with `allow`. Its input has the tool name and arguments, but the user is hard-coded to `"none"` and there is no server name. An adapter package exposing `allow` could route to one pack per configured tool, but not authorize by identity until the plugin sends one.
