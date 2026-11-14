#!/bin/sh
# End-to-end test of integrations/opa-sidecar: start the compose example from the
# built bundles and check one allowed and one denied call over HTTP.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

compose="docker compose --file integrations/opa-sidecar/docker-compose.yml"
url="http://127.0.0.1:8181"

for bundle in dist/mcp-policy-library.tar.gz dist/config.tar.gz; do
	[ -f "$bundle" ] || {
		echo "$bundle not found; run make bundle config-bundle" >&2
		exit 1
	}
done

work="$(mktemp -d)"
cleanup() {
	$compose logs >"$work/compose.log" 2>&1 || true
	$compose down --volumes >/dev/null 2>&1 || true
	rm -r "$work"
}
trap cleanup EXIT

$compose up --detach

attempts=0
until curl -fsS "$url/health?bundles=true" >/dev/null 2>&1; do
	attempts=$((attempts + 1))
	if [ "$attempts" -gt 60 ]; then
		echo "sidecar did not become healthy" >&2
		$compose logs >&2 || true
		exit 1
	fi
	sleep 1
done

failures=0
check() {
	{
		printf '{"input":'
		cat "$1"
		printf '}'
	} >"$work/request.json"
	curl -fsS -H 'Content-Type: application/json' --data-binary "@$work/request.json" \
		"$url/v1/data/mcp/main/decision" >"$work/response.json"
	if opa eval --fail --input "$work/response.json" "$2" >/dev/null 2>&1; then
		echo "ok:   $1"
	else
		echo "FAIL: $1 returned $(cat "$work/response.json")"
		failures=$((failures + 1))
	fi
}

# A query of one comparison passes --fail even when it is false, so each check has several.
check examples/github-pull-request-allowed/input.json 'input.result.allow == true; input.result.require_approval == false; count(input.result.deny) == 0'
check examples/github-push-to-main-denied/input.json 'input.result.allow == false; input.result.deny[0].code == "github.protected_branch"'

[ "$failures" -eq 0 ]
