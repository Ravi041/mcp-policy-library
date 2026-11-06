#!/bin/sh
# A minimal MCP client over Streamable HTTP, enough to drive the walkthrough with curl.
#
#   mcp-client.sh <url> <method> [params-json]
#
# Prints "HTTP <status>" on the first line, then the JSON-RPC message the server returned
# (unwrapped from server-sent events when needed).
#
#   MCP_TOKEN         bearer token to send, if set
#   MCP_SESSION_FILE  where the session id is kept between calls (default: .mcp-session)
#
# Run `initialize` and then `notifications/initialized` once per session before other calls.
set -eu

url=$1 method=$2 params=${3:-'{}'}
session_file=${MCP_SESSION_FILE:-.mcp-session}
counter_file="$session_file.id"

# A new session starts with no session id and request ids from 1.
case $method in
initialize)
	: >"$session_file"
	echo 0 >"$counter_file"
	;;
esac

last_id=$(cat "$counter_file" 2>/dev/null || echo 0)
id=$((last_id + 1))
echo "$id" >"$counter_file"

case $method in
notifications/*) payload=$(printf '{"jsonrpc":"2.0","method":"%s"}' "$method") ;;
*) payload=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params") ;;
esac

headers=$(mktemp)
body=$(mktemp)
trap 'rm -f "$headers" "$body"' EXIT

set -- -s --max-time 60 -D "$headers" -o "$body" -w '%{http_code}' -X POST "$url" \
	-H 'Content-Type: application/json' \
	-H 'Accept: application/json, text/event-stream' \
	-H 'MCP-Protocol-Version: 2025-06-18'
if [ -n "${MCP_TOKEN:-}" ]; then
	set -- "$@" -H "Authorization: Bearer $MCP_TOKEN"
fi
if [ -s "$session_file" ]; then
	set -- "$@" -H "Mcp-Session-Id: $(cat "$session_file")"
fi

status=$(curl "$@" --data "$payload" || true)

session=$(tr -d '\r' <"$headers" | awk 'tolower($1) == "mcp-session-id:" {print $2}')
if [ -n "$session" ]; then
	printf '%s' "$session" >"$session_file"
fi

echo "HTTP $status"
if grep -q '^data: ' "$body"; then
	sed -n 's/^data: //p' "$body"
else
	cat "$body"
	echo
fi
