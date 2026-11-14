# OPA sidecar

Run OPA next to your gateway or agent runtime, and ask it for a decision before every tool call. This works with anything that can make an HTTP request.

## Run it

From the repository root:

```sh
make tools                   # pinned opa and regal in .bin/
make bundle config-bundle    # dist/mcp-policy-library.tar.gz and dist/config.tar.gz
docker compose --file integrations/opa-sidecar/docker-compose.yml up --detach
```

The compose file pins the OPA image by digest and listens only on `127.0.0.1:8181`. The container's filesystem is read-only, and the bundles are mounted read-only.

Without Docker, the same server runs from the binary:

```sh
.bin/opa run --server --addr 127.0.0.1:8181 \
  --bundle dist/mcp-policy-library.tar.gz --bundle dist/config.tar.gz
```

## Ask for a decision

```sh
curl -s -H 'Content-Type: application/json' \
  --data "{\"input\": $(cat examples/github-push-to-main-denied/input.json)}" \
  http://127.0.0.1:8181/v1/data/mcp/main/decision
```

The decision is in the `result` field of the response:

```json
{"result": {"allow": false, "deny": [{"code": "github.protected_branch", "message": "branch \"main\" is protected; open a pull request instead", "pack": "github"}], "obligations": {"audit_tags": ["github:write", "pack:github"]}, "policy_version": "0.1.4", "require_approval": false}}
```

## Use your own configuration

The policy bundle owns the `mcp` root and the config bundle owns `mcp_config`. Because the two never overlap, you can update configuration without rebuilding or redeploying the policy.

Write one or more files shaped like the packs' `data.example.json`, then build them into a config bundle:

```sh
sh scripts/build-config-bundle.sh dist/config.tar.gz my-config.json
```

In production, serve both bundles from a bundle server or OCI registry and point OPA at them with a configuration file instead of mounting local files. OPA then polls for new versions. See the [OPA bundle documentation](https://www.openpolicyagent.org/docs/management-bundles).

## Failing closed

Treat each of these as a deny:

- a connection error or timeout
- any HTTP status other than 200
- a response with no `result` field, which is what a wrong query path returns

`make e2e` checks the last two against a real server.
