# Changelog

Each release's `policy_version` matches its tag. Every decision carries it, so you can tell which rules made a decision.

## 0.1.1

### Security

- **postgres:** `denied_schemas` could be bypassed by functions that take a table, schema or query as a string. `table_to_xml('secrets.tokens', ...)`, `schema_to_xml`, `database_to_xml`, their `_and_xmlschema` forms, `ts_rewrite` and `pg_logical_slot_peek_changes` returned rows from a denied schema on PostgreSQL 17.11. They are now blocked functions.
- **postgres:** Blocked functions with side effects that the list missed: `pg_notify`, advisory locks, large-object writes (`lo_creat`, `lowrite`, `lo_truncate`), BRIN and GIN index maintenance, statistics resets, WAL messages, replication slots and origins, and server control such as `pg_promote`. See the [full list](packs/postgres/README.md#blocked-functions).

### Added

- agentgateway adapter and a [runbook](docs/try-it-with-gateways.md) for trying the library behind a real MCP gateway.
- A status section in the README.
- Release bundles carry a GitHub build provenance attestation.

### Fixed

- The agentgateway walkthrough's forged-token check failed about one run in four, because it edited a base64url character that carries no signature data.

## 0.1.0

First release: the `baseline`, `filesystem`, `github` and `postgres` packs, the input and decision schemas, the OPA sidecar and Docker Compose integrations, and examples.
