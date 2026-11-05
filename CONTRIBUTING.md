# Contributing

Thanks for helping. Bug reports, new packs and fixes to existing packs are all welcome.

## Before you start

- **Open an issue first** for a new pack or a change to the input or decision schema. Schema changes affect every integration, so they are agreed before they are written.
- **Read the design principles** in [CLAUDE.md](CLAUDE.md). The QA gates enforce most of them, and changes that break them will not be merged. In short: no gateway-specific fields in policies, default deny, configuration through data, a stable code for every deny, no allow based only on tool annotations, and only verified tool names.

## Development

```sh
make tools                   # pinned OPA and Regal in .bin/
export PATH="$PWD/.bin:$PATH"
make ci                      # everything CI runs, except the Docker test
```

[docs/testing.md](docs/testing.md) describes every test layer, and [docs/writing-a-pack.md](docs/writing-a-pack.md) walks through adding a pack.

## Pull requests

- **Write tests first.** A change to a rule comes with a test that fails without it.
- **Explain your choices.** Say how you verified any tool name or argument shape: link the server's source at a release tag.
- **Keep packs up to date.** Update the pack README when you add or change a deny code or config key.
- **Use conventional commit messages,** for example `feat(github): ...`, `fix(filesystem): ...`, `docs: ...`.
- **Ask first about new dependencies.** Discuss any dependency beyond OPA and Regal in an issue first, including a new GitHub Action from outside the `actions/` organization.

## Releases

A release is a `vX.Y.Z` tag that matches `policy_version` in `policies/mcp/main/main.rego`. The `ci` workflow checks that match and attaches the bundle to the GitHub release.

Deny codes are stable within a major version. Removing or renaming one, or making a pack stricter in a way that breaks existing configurations, needs a major version.
