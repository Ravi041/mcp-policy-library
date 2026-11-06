#!/bin/sh
# Print total coverage and any Rego file below 100% from `opa test --coverage` output.
set -eu

report="${1:-coverage.json}"

opa eval --format=raw --input "$report" 'sprintf("total coverage: %.2f%%", [input.coverage])'
echo
opa eval --format=raw --input "$report" \
	'concat("\n", [line | some file, entry in input.files; entry.coverage < 100; line := sprintf("  %6.2f%%  %s", [entry.coverage, file])])'
echo
