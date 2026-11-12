#!/bin/sh
# End-to-end test: run a real OPA server from the built bundles, exactly as an
# integration would, and check decisions over HTTP.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

# shellcheck source=scripts/lib.sh
. scripts/lib.sh

policy_bundle="dist/mcp-policy-library.tar.gz"
port="${E2E_PORT:-18181}"
bare_port="${E2E_BARE_PORT:-18182}"
query_path="v1/data/mcp/main/decision"

if [ ! -f "$policy_bundle" ]; then
	echo "$policy_bundle not found; run make bundle" >&2
	exit 1
fi

work="$(mktemp -d)"
server_pid=""
bare_pid=""
cleanup() {
	[ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
	[ -z "$bare_pid" ] || kill "$bare_pid" 2>/dev/null || true
	rm -r "$work"
}
trap cleanup EXIT

failures=0
checked=0
fail() {
	echo "FAIL $1: $2"
	failures=$((failures + 1))
}

wait_for() {
	attempts=0
	until curl -fsS "http://127.0.0.1:$1/health?bundles=true" >/dev/null 2>&1; do
		attempts=$((attempts + 1))
		if [ "$attempts" -gt 50 ]; then
			echo "OPA on port $1 did not become healthy; log follows" >&2
			cat "$2" >&2
			exit 1
		fi
		sleep 0.2
	done
}

# POST a fixture as {"input": ...} and write the decision (the result field) to $work/decision.json.
decide() {
	{
		printf '{"input":'
		cat "$2"
		printf '}'
	} >"$work/request.json"
	curl -fsS -H 'Content-Type: application/json' --data-binary "@$work/request.json" \
		"http://127.0.0.1:$1/$query_path" >"$work/response.json"
	opa eval --format=raw --input "$work/response.json" 'input.result' >"$work/decision.json"
}

# Build a separate config bundle from the example data, as a deployment would.
sh scripts/build-config-bundle.sh "$work/config.tar.gz" >/dev/null

opa run --server --addr "127.0.0.1:$port" --log-level error \
	--bundle "$policy_bundle" --bundle "$work/config.tar.gz" >"$work/server.log" 2>&1 &
server_pid=$!
wait_for "$port" "$work/server.log"

opa run --server --addr "127.0.0.1:$bare_port" --log-level error \
	--bundle "$policy_bundle" >"$work/bare.log" 2>&1 &
bare_pid=$!
wait_for "$bare_port" "$work/bare.log"

# Scenario 1: every fixture gets its expected outcome over HTTP, and the decision matches the contract.
for fixture in packs/*/fixtures/*.json; do
	checked=$((checked + 1))
	stem="$(basename "$fixture" .json)"
	decide "$port" "$fixture"
	errors="$(opa eval --format=raw --input "$work/decision.json" --data schemas/decision.schema.json \
		'concat("; ", [e.error | some e in json.match_schema(input, data)[1]])')"
	[ -z "$errors" ] || fail "$fixture" "decision breaks the schema: $errors"
	query="$(expected_outcome_query "$stem")"
	opa eval --fail --input "$work/decision.json" "$query" >/dev/null 2>&1 ||
		fail "$fixture" "unexpected decision: $(cat "$work/decision.json")"
done

# Scenario 2: every example returns exactly its recorded decision.
for example in examples/*/; do
	[ -f "${example}input.json" ] || continue
	checked=$((checked + 1))
	decide "$port" "${example}input.json"
	opa eval --fail --input "$work/decision.json" --data "${example}decision.json" 'input = data' >/dev/null 2>&1 ||
		fail "$example" "decision differs: $(cat "$work/decision.json")"
done

# Scenario 3: with the policy bundle but no config, nothing is allowed. Config can only open access.
for fixture in packs/*/fixtures/allow_*.json packs/*/fixtures/approve_*.json; do
	[ -f "$fixture" ] || continue
	checked=$((checked + 1))
	stem="$(basename "$fixture" .json)"
	decide "$bare_port" "$fixture"
	case "$stem" in
	# Read-only SQL is the documented default of the postgres pack and needs no config.
	allow_postgres_default_*)
		;;
	*)
		opa eval --fail --input "$work/decision.json" 'input.allow == false; input.require_approval == false; count(input.deny) > 0' >/dev/null 2>&1 ||
			fail "$fixture" "allowed with no config: $(cat "$work/decision.json")"
		;;
	esac
done

# Scenario 4: an empty document and a request with no input still produce a full, refusing decision.
checked=$((checked + 2))
printf '{}' >"$work/empty.json"
decide "$port" "$work/empty.json"
opa eval --fail --input "$work/decision.json" 'input.allow == false; some d in input.deny; d.code == "main.invalid_input"' >/dev/null 2>&1 ||
	fail "empty input" "unexpected decision: $(cat "$work/decision.json")"
curl -fsS -X POST "http://127.0.0.1:$port/$query_path" >"$work/response.json"
opa eval --fail --input "$work/response.json" 'input.result.allow == false; some d in input.result.deny; d.code == "main.invalid_input"' >/dev/null 2>&1 ||
	fail "no input" "unexpected response: $(cat "$work/response.json")"

# Scenario 5: malformed JSON is an HTTP error. Integrations must treat any non-200 as a deny.
checked=$((checked + 1))
status="$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary '{"input":' "http://127.0.0.1:$port/$query_path")"
[ "$status" = 400 ] || fail "malformed JSON" "expected HTTP 400, got $status"

# Scenario 6: a wrong query path returns no result, which integrations must also treat as a deny.
checked=$((checked + 1))
curl -fsS -H 'Content-Type: application/json' --data-binary '{"input":{}}' "http://127.0.0.1:$port/v1/data/mcp/main/not_a_rule" >"$work/response.json"
opa eval --fail --input "$work/response.json" 'not input.result' >/dev/null 2>&1 ||
	fail "wrong path" "expected no result, got $(cat "$work/response.json")"

echo "ran $checked end-to-end checks, $failures failed"
[ "$failures" -eq 0 ]
