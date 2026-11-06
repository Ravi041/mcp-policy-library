# Kavrynt

Documentation only. Kavrynt's policy-loading API is not confirmed yet, so this directory has no code and makes no claims about Kavrynt's configuration format. It will be filled in once that API is confirmed.

Whatever Kavrynt's loading mechanism turns out to be, an integration needs the same four things as any other gateway, described in [the adapter guide](../README.md):

1. **Load the policy.** Use `mcp-policy-library.tar.gz` from a GitHub release, or `make bundle`. Its root is `mcp`.
2. **Load configuration separately.** The root is `mcp_config`, shaped like the packs' `data.example.json` files.
3. **Build the input.** Map each tool call onto `schemas/input.schema.json`, with `server.name` and `principal` coming from Kavrynt's own configuration and identity, never from the agent. Kavrynt-specific values go in `server.labels` or `context.labels`.
4. **Enforce the decision.** Query `data.mcp.main.decision`, and treat any error, missing result, `allow: false` or `require_approval: true` as "do not run yet".

Nothing Kavrynt-specific may be added to `policies/`.
