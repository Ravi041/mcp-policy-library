#!/bin/sh
# Replay recorded tool calls against the current policies and report every call
# whose outcome moved. Uses only OPA and POSIX tools.
#
#   sh scripts/replay.sh <trace> [config.json ...]
#
# <trace> is an OPA decision log, one JSON record per line, as written by
# `opa run --server --set decision_logs.console=true`. Other lines are ignored.
# Records logged at data.mcp.main.decision and at the agentgateway adapter are
# replayed; anything else is skipped.
#
# The config files must be the ones that were live when the trace was recorded.
# A decision log does not hold them.
#
# A call fails the replay when its outcome moved in either direction:
#   LOOSENED   refused or held before, more open now      a security regression
#   TIGHTENED  allowed before, refused or held now        a usability regression
# and when an input that was allowed breaks the input schema. A changed deny
# code on a call that is still refused is reported and does not fail.
#
# Environment:
#   REPLAY_POLICY   policy directory or bundle to test. Default: policies/
#   REPLAY_ACCEPT   file of decision IDs, one per line, whose move was reviewed
#                   and is intended. Lines starting with # are ignored.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$#" -lt 1 ]; then
	echo "usage: sh scripts/replay.sh <trace> [config.json ...]" >&2
	exit 2
fi

# Resolve the caller's paths before moving to the repository root.
absolute() {
	case "$1" in
	/*) echo "$1" ;;
	*) echo "$PWD/$1" ;;
	esac
}

trace="$(absolute "$1")"
shift
if [ ! -f "$trace" ]; then
	echo "trace not found: $trace" >&2
	exit 2
fi

work="$(mktemp -d)"
trap 'rm -r "$work"' EXIT

# One path per line, so paths with spaces survive.
: >"$work/configs"
for file in "$@"; do
	if [ ! -f "$file" ]; then
		echo "config not found: $file" >&2
		exit 2
	fi
	absolute "$file" >>"$work/configs"
done

policy="policies/"
[ -z "${REPLAY_POLICY:-}" ] || policy="$(absolute "$REPLAY_POLICY")"

accept=""
if [ -n "${REPLAY_ACCEPT:-}" ]; then
	accept="$(absolute "$REPLAY_ACCEPT")"
	if [ ! -f "$accept" ]; then
		echo "accept file not found: $accept" >&2
		exit 2
	fi
fi

cd "$root"

# Decision-log records are the lines that carry a decision ID. A server log
# also holds start-up and error lines, which are not records.
grep '"decision_id"' "$trace" >"$work/records" || true
if [ ! -s "$work/records" ]; then
	echo "no decision-log records in $trace" >&2
	exit 1
fi

# The accepted IDs as a JSON list. IDs are restricted to a safe alphabet, so
# nothing in the file can break out of its string.
: >"$work/accepted"
if [ -n "$accept" ]; then
	grep -v '^[[:space:]]*#' "$accept" | tr -d ' \t\r' | grep -E '^[A-Za-z0-9._:-]+$' |
		sed 's/.*/"&"/' | paste -s -d , - >"$work/accepted" || true
fi

# One input document: the records, both schemas and the accepted IDs.
{
	printf '{"records":['
	paste -s -d , "$work/records"
	printf '],"input_schema":'
	cat schemas/input.schema.json
	printf ',"decision_schema":'
	cat schemas/decision.schema.json
	printf ',"accepted":['
	cat "$work/accepted"
	printf ']}'
} >"$work/input.json"

# A bundle file is loaded as a bundle; a directory of Rego as plain data.
set -- --data scripts/replay/mcp_replay/replay.rego \
	--data integrations/agentgateway/policy/mcp_adapters/agentgateway/adapter.rego
if [ -d "$policy" ]; then
	set -- "$@" --data "$policy" --ignore '*_test.rego'
else
	set -- "$@" --bundle "$policy"
fi
while IFS= read -r file; do
	set -- "$@" --data "$file"
done <"$work/configs"

if ! opa eval --format=raw --input "$work/input.json" "$@" 'data.mcp_replay.report' >"$work/report.json"; then
	echo "could not evaluate the trace; is every decision-log line valid JSON?" >&2
	exit 1
fi

opa eval --format=raw --input "$work/report.json" 'concat("\n", input.lines)'
echo
opa eval --fail --input "$work/report.json" 'input.ok = true' >/dev/null 2>&1
