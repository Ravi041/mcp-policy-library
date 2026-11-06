# Security policy

This library makes authorization decisions, so a bug that allows a call it should deny is a security vulnerability. Examples:

- a path, branch or SQL form that slips past a pack
- an input shape that makes a deny rule silently not fire
- a decision that is allowed without a matching allow rule

## Reporting a vulnerability

Report it privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Please do not open a public issue or pull request for a vulnerability.

Include:

- the input document, and the configuration that produces the wrong decision
- the decision you got, and the one you expected
- the library version (`policy_version` in the decision) and the OPA version

You will get an acknowledgement, and a fix will be developed in a private advisory before it is published.

## Supported versions

Only the latest release receives security fixes during the 0.x series.

## Scope

In scope:

- the Rego policies
- the schemas
- the scripts in this repository

Out of scope, though reports are still appreciated:

- **Server vulnerabilities.** Weaknesses in the MCP servers themselves.
- **Integration code.** The gateways and integrations that load this library.
- **Documented limitations.** Gaps already listed in a pack README, such as SQL inspection being best-effort, symlinks being invisible to path checks, and tool-call policy not covering MCP resources.
