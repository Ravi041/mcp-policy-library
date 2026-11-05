#!/bin/sh
# Validate every fixture and example against the schemas, then evaluate it and
# check the outcome. Uses only OPA and POSIX tools.
#
# The expected outcome of a fixture comes from its file name:
#   allow_<description>.json              allow is true
#   approve_<description>.json            require_approval is true, allow is false
#   deny_<code>[--<description>].json     allow is false and deny contains <code>
#
# An example is a directory holding input.json and decision.json. Its decision
# must match decision.json exactly.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

# shellcheck source=scripts/lib.sh
. scripts/lib.sh

work="$(mktemp -d)"
trap 'rm -f "$work"/*; rmdir "$work"' EXIT

data_args=""
for file in packs/*/data.example.json; do
	data_args="$data_args --data $file"
done

failures=0
checked=0

fail() {
	echo "FAIL $1: $2"
	failures=$((failures + 1))
}

schema_errors() {
	opa eval --format=raw --input "$1" --data "$2" \
		'concat("; ", [e.error | some e in json.match_schema(input, data)[1]])'
}

evaluate() {
	# shellcheck disable=SC2086 # data_args is a list of flags
	opa eval --format=raw --input "$1" --data policies/ $data_args 'data.mcp.main.decision' >"$work/decision.json"
}

for fixture in packs/*/fixtures/*.json; do
	checked=$((checked + 1))
	stem="$(basename "$fixture" .json)"

	errors="$(schema_errors "$fixture" schemas/input.schema.json)"
	if [ -n "$errors" ]; then
		fail "$fixture" "not valid against input schema: $errors"
		continue
	fi

	evaluate "$fixture"

	errors="$(schema_errors "$work/decision.json" schemas/decision.schema.json)"
	if [ -n "$errors" ]; then
		fail "$fixture" "decision not valid against decision schema: $errors"
		continue
	fi

	if ! query="$(expected_outcome_query "$stem")"; then
		fail "$fixture" "file name must start with allow_, approve_ or deny_"
		continue
	fi

	if ! opa eval --fail --input "$work/decision.json" "$query" >/dev/null 2>&1; then
		fail "$fixture" "unexpected decision: $(cat "$work/decision.json")"
	fi
done

for example in examples/*/; do
	[ -f "${example}input.json" ] || continue
	checked=$((checked + 1))

	errors="$(schema_errors "${example}input.json" schemas/input.schema.json)"
	if [ -n "$errors" ]; then
		fail "$example" "input not valid: $errors"
		continue
	fi

	evaluate "${example}input.json"

	if ! opa eval --fail --input "$work/decision.json" --data "${example}decision.json" 'input == data' >/dev/null 2>&1; then
		fail "$example" "decision differs from decision.json: $(cat "$work/decision.json")"
	fi
done

echo "checked $checked fixtures and examples, $failures failed"
[ "$failures" -eq 0 ]
