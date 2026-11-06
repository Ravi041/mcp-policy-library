#!/bin/sh
# Run the policy library behind agentgateway, with real MCP servers, and check what happens.
#
#   try.sh          start everything, run every scenario, stop everything
#   try.sh up       start everything and leave it running, to connect your own MCP client
#   try.sh check    run the scenarios against a running stack; they expect the default
#                   configuration that `up` writes to $WORK/config/data.json
#   try.sh down     stop everything
#
# Environment:
#   BUNDLE      policy bundle to load (default: dist/mcp-policy-library.tar.gz, from
#               `make bundle` or the GitHub release asset)
#   WORK        scratch directory (default: .try/agentgateway, which git ignores)
#   GITHUB=0    skip the GitHub server (default: on when .bin/github-mcp-server exists)
#   POSTGRES=0  skip Postgres (default: on when Docker is running)
#
# Ports: gateway 3000, OPA ext_authz gRPC 9191, OPA HTTP API 8181, Postgres 55432.
set -eu

here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"
bin="$root/.bin"
WORK=${WORK:-$root/.try/agentgateway}
BUNDLE=${BUNDLE:-$root/dist/mcp-policy-library.tar.gz}

GATEWAY_PORT=3000
AUTHZ_PORT=9191
OPA_PORT=8181
PG_PORT=55432
PG_CONTAINER=mcp-policy-try-postgres
POSTGRES_IMAGE=postgres@sha256:3540c0362c809df084ffac0ae69fe794515f9de92692f02178bcdce0ef0302ac # 17.11-alpine
POSTGRES_MCP_IMAGE=crystaldba/postgres-mcp@sha256:dbbd346860d29f1543e991f30f3284bf4ab5f096d049ecc3426528f20b1b6e6b # 0.3.0

gateway="http://127.0.0.1:$GATEWAY_PORT"
PATH="$bin:$PATH"
export PATH

github_enabled() {
	[ "${GITHUB:-1}" = 1 ] && [ -x "$bin/github-mcp-server" ]
}

postgres_enabled() {
	[ "${POSTGRES:-1}" = 1 ] && docker info >/dev/null 2>&1
}

need() {
	for tool in "$@"; do
		command -v "$tool" >/dev/null 2>&1 || {
			echo "missing $tool; see integrations/agentgateway/README.md" >&2
			exit 1
		}
	done
}

wait_for() { # wait_for <description> <command...>
	what=$1
	shift
	tries=0
	until "$@" >/dev/null 2>&1; do
		tries=$((tries + 1))
		if [ "$tries" -ge 120 ]; then
			echo "timed out waiting for $what" >&2
			exit 1
		fi
		sleep 0.5
	done
}

gateway_rejects_anonymous() {
	[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$gateway/filesystem/mcp")" = 401 ]
}

start_opa() {
	opa-envoy run --server --skip-version-check \
		--addr "127.0.0.1:$OPA_PORT" --diagnostic-addr "127.0.0.1:$((OPA_PORT + 1))" \
		--set "plugins.envoy_ext_authz_grpc.addr=127.0.0.1:$AUTHZ_PORT" \
		--set plugins.envoy_ext_authz_grpc.path=mcp_adapters/agentgateway/response \
		--set decision_logs.console=true \
		--ignore '*_test.rego' \
		--bundle "$BUNDLE" --bundle "$here/policy" --bundle "$WORK/config" \
		>>"$WORK/opa.log" 2>&1 &
	echo $! >"$WORK/opa.pid"
	wait_for "OPA" curl -sf "http://127.0.0.1:$((OPA_PORT + 1))/health?bundles"
}

stop_pid() {
	if [ -s "$WORK/$1.pid" ]; then
		kill "$(cat "$WORK/$1.pid")" 2>/dev/null || true
		: >"$WORK/$1.pid"
	fi
}

up() {
	need opa-envoy agentgateway npx curl openssl xxd
	if [ ! -f "$BUNDLE" ]; then
		echo "no policy bundle at $BUNDLE; run 'make bundle' or download the release asset" >&2
		exit 1
	fi
	mkdir -p "$WORK/workspace/projects/app/tmp" "$WORK/workspace/secrets" "$WORK/config" "$WORK/sessions"

	[ -f "$WORK/keys/jwks.json" ] || sh "$here/dev-token.sh" keys "$WORK/keys"
	sh "$here/dev-token.sh" token "$WORK/keys" alice@example.com >"$WORK/token"

	echo 'hello from the allowed project' >"$WORK/workspace/projects/app/README.md"
	echo 'API_KEY=not-a-real-secret' >"$WORK/workspace/projects/app/.env"
	echo 'not a real secret' >"$WORK/workspace/secrets/keys.txt"

	# Configuration bundle: who may do what. Paths are absolute, as the filesystem pack requires.
	# An existing data.json is kept, so you can edit it and run `up` again.
	echo '{"roots":["mcp_config"]}' >"$WORK/config/.manifest"
	[ -f "$WORK/config/data.json" ] || cat >"$WORK/config/data.json" <<EOF
{
  "mcp_config": {
    "baseline": {
      "allowed_servers": ["filesystem", "github", "postgres"],
      "destructive_allowlist": {"filesystem": ["write_file", "edit_file", "move_file"]}
    },
    "filesystem": {
      "read_paths": ["$WORK/workspace/projects"],
      "write_paths": ["$WORK/workspace/projects/app/tmp"],
      "deny_globs": ["**/.env", "**/.env.*", "**/*.pem"]
    },
    "github": {
      "allowed_repos": ["octo-org/demo"],
      "protected_branches": ["main"],
      "allow_merge": true,
      "require_approval_tools": ["merge_pull_request"]
    },
    "postgres": {
      "denied_schemas": ["secrets"]
    }
  }
}
EOF

	sed -e "s|@WORK@|$WORK|g" -e "s|@BIN@|$bin|g" \
		-e "s|@GATEWAY_PORT@|$GATEWAY_PORT|g" -e "s|@AUTHZ_PORT@|$AUTHZ_PORT|g" \
		-e "s|@PG_PORT@|$PG_PORT|g" -e "s|@POSTGRES_MCP_IMAGE@|$POSTGRES_MCP_IMAGE|g" \
		"$here/agentgateway.template.yaml" >"$WORK/agentgateway.yaml"
	agentgateway -f "$WORK/agentgateway.yaml" --validate-only >/dev/null

	if postgres_enabled; then
		mkdir -p "$WORK/pg-init"
		cat >"$WORK/pg-init/demo.sql" <<'EOF'
CREATE TABLE public.orders (id int PRIMARY KEY, customer text NOT NULL, total numeric NOT NULL);
INSERT INTO public.orders VALUES (1, 'ada', 10.50), (2, 'grace', 22.00), (3, 'linus', 7.25);
CREATE SCHEMA secrets;
CREATE TABLE secrets.api_keys (name text, value text);
INSERT INTO secrets.api_keys VALUES ('payments', 'not-a-real-key');
EOF
		docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
		docker run -d --name "$PG_CONTAINER" -p "127.0.0.1:$PG_PORT:5432" \
			-e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
			-v "$WORK/pg-init:/docker-entrypoint-initdb.d:ro" "$POSTGRES_IMAGE" >/dev/null
		wait_for "Postgres" docker exec "$PG_CONTAINER" psql -U demo -d demo -tAc 'SELECT count(*) FROM public.orders'
	fi

	: >"$WORK/opa.log"
	start_opa
	agentgateway -f "$WORK/agentgateway.yaml" >"$WORK/agentgateway.log" 2>&1 &
	echo $! >"$WORK/agentgateway.pid"
	wait_for "agentgateway" gateway_rejects_anonymous

	cat <<EOF
Running.
  gateway       $gateway/{filesystem,github,postgres,everything}/mcp
  token         $WORK/token  (send as: Authorization: Bearer <token>)
  OPA decisions $WORK/opa.log
  gateway log   $WORK/agentgateway.log
EOF
}

down() {
	stop_pid agentgateway
	stop_pid opa
	docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
	echo "Stopped."
}

# --- Scenarios -------------------------------------------------------------------------------

passed=0
failed=0
skipped=0

# call <route> <method> [params]: one MCP request with alice's token; prints status and message.
call() {
	params=${3-}
	[ -n "$params" ] || params='{}'
	MCP_TOKEN=$(cat "$WORK/token") MCP_SESSION_FILE="$WORK/sessions/$1" \
		sh "$here/mcp-client.sh" "$gateway/$1/mcp" "$2" "$params"
}

open_session() {
	call "$1" initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"try.sh","version":"0"}}' >/dev/null
	call "$1" notifications/initialized >/dev/null
}

# outcome: classify a reply read from stdin as one word.
#   allowed            the server answered with a result
#   forwarded-failed   the policy let it through; the server or upstream reported an error
#   refused:<codes>    the policy refused it; codes are the adapter and library deny codes
#   http:<status>      no JSON-RPC answer at all
outcome() {
	reply=$(cat)
	status=$(printf '%s\n' "$reply" | sed -n '1s/^HTTP //p')
	message=$(printf '%s\n' "$reply" | sed -n '2,$p')
	if [ "$status" != 200 ]; then
		echo "http:$status"
		return
	fi
	printf '%s' "$message" | opa eval --stdin-input --format raw --data "$WORK/outcome.rego" \
		data.outcome.word 2>/dev/null || echo unparsed
}

write_outcome_policy() {
	cat >"$WORK/outcome.rego" <<'EOF'
package outcome

codes := concat(",", array.concat([input.error.data.code], [r.code | some r in object.get(input.error.data, ["decision", "deny"], [])]))

default word := "unparsed"

word := sprintf("refused:%s", [codes]) if input.error.code == -32001

word := "forwarded-failed" if {
	input.error
	input.error.code != -32001
}

word := "forwarded-failed" if input.result.isError == true

word := "allowed" if {
	input.result
	not input.result.isError == true
}
EOF
}

# expect <description> <expected> <route> <method> [params]
#   expected is "allowed", "forwarded-failed", "http:<status>" or "refused:<code>", where the
#   refusal passes when <code> is among the refusal's codes.
expect() {
	description=$1 expected=$2
	shift 2
	got=$(call "$@" | outcome)
	case $expected in
	refused:*) ok=$(printf ',%s,' "${got#refused:}" | grep -c ",${expected#refused:},") || true ;;
	*) ok=$([ "$got" = "$expected" ] && echo 1 || echo 0) ;;
	esac
	if [ "$ok" = 1 ]; then
		passed=$((passed + 1))
		printf '  PASS  %-58s %s\n' "$description" "$got"
	else
		failed=$((failed + 1))
		printf '  FAIL  %-58s expected %s, got %s\n' "$description" "$expected" "$got"
	fi
}

verify() { # verify <description> <command...>: a side effect check
	description=$1
	shift
	if "$@" >/dev/null 2>&1; then
		passed=$((passed + 1))
		printf '  PASS  %s\n' "$description"
	else
		failed=$((failed + 1))
		printf '  FAIL  %s\n' "$description"
	fi
}

skip() {
	skipped=$((skipped + 1))
	printf '  SKIP  %s\n' "$1"
}

order_count_is_3() {
	[ "$(docker exec "$PG_CONTAINER" psql -U demo -d demo -tAc 'SELECT count(*) FROM public.orders')" = 3 ]
}

check() {
	need curl opa
	ws="$WORK/workspace"
	write_outcome_policy

	echo "Identity, enforced by the gateway before OPA is asked"
	verify "no token is rejected with HTTP 401" sh -c "MCP_SESSION_FILE='$WORK/sessions/anon' sh '$here/mcp-client.sh' '$gateway/filesystem/mcp' tools/list | grep -q '^HTTP 401'"
	verify "a token from another key is rejected with HTTP 401" sh -c "MCP_TOKEN='$(cat "$WORK/token" | sed 's/.$/A/')' MCP_SESSION_FILE='$WORK/sessions/anon' sh '$here/mcp-client.sh' '$gateway/filesystem/mcp' tools/list | grep -q '^HTTP 401'"

	echo "filesystem pack"
	open_session filesystem
	expect "tools/list passes" allowed filesystem tools/list
	expect "read a file in an allowed directory" allowed filesystem tools/call \
		"{\"name\":\"read_text_file\",\"arguments\":{\"path\":\"$ws/projects/app/README.md\"}}"
	expect "read outside the allowed directories" refused:filesystem.path_not_allowed filesystem tools/call \
		"{\"name\":\"read_text_file\",\"arguments\":{\"path\":\"$ws/secrets/keys.txt\"}}"
	expect "read a .env file" refused:filesystem.path_denied filesystem tools/call \
		"{\"name\":\"read_text_file\",\"arguments\":{\"path\":\"$ws/projects/app/.env\"}}"
	expect "climb out with .." refused:filesystem.path_traversal filesystem tools/call \
		"{\"name\":\"read_text_file\",\"arguments\":{\"path\":\"$ws/projects/../secrets/keys.txt\"}}"
	expect "relative path" refused:filesystem.path_not_absolute filesystem tools/call \
		'{"name":"read_text_file","arguments":{"path":"projects/app/README.md"}}'
	expect "write inside the write directory" allowed filesystem tools/call \
		"{\"name\":\"write_file\",\"arguments\":{\"path\":\"$ws/projects/app/tmp/notes.txt\",\"content\":\"written through the gateway\"}}"
	verify "  ...and the file exists" test -f "$ws/projects/app/tmp/notes.txt"
	expect "write outside the write directory" refused:filesystem.path_not_allowed filesystem tools/call \
		"{\"name\":\"write_file\",\"arguments\":{\"path\":\"$ws/projects/app/README.md\",\"content\":\"overwritten\"}}"
	verify "  ...and the file is unchanged" grep -q 'hello from the allowed project' "$ws/projects/app/README.md"
	expect "a tool the pack does not name" refused:filesystem.tool_not_supported filesystem tools/call \
		'{"name":"delete_everything","arguments":{}}'
	expect "resources/read, which tool rules cannot see" refused:adapter.method_not_allowed filesystem resources/read \
		"{\"uri\":\"file://$ws/secrets/keys.txt\"}"

	echo "baseline pack"
	open_session everything
	expect "a server the configuration does not list" refused:baseline.server_not_allowed everything tools/call \
		'{"name":"echo","arguments":{"message":"hi"}}'

	echo "github pack"
	if github_enabled; then
		open_session github
		expect "read in an allowed repo (reaches GitHub, fake token)" forwarded-failed github tools/call \
			'{"name":"get_file_contents","arguments":{"owner":"octo-org","repo":"demo","path":"README.md"}}'
		expect "read in another repo" refused:github.repo_not_allowed github tools/call \
			'{"name":"get_file_contents","arguments":{"owner":"someone","repo":"else","path":"README.md"}}'
		expect "push straight to main" refused:github.protected_branch github tools/call \
			'{"name":"push_files","arguments":{"owner":"octo-org","repo":"demo","branch":"main","message":"m","files":[{"path":"a.txt","content":"a"}]}}'
		expect "edit a workflow file" refused:github.protected_path github tools/call \
			'{"name":"create_or_update_file","arguments":{"owner":"octo-org","repo":"demo","branch":"feature","path":".github/workflows/ci.yml","content":"x","message":"m"}}'
		expect "merge, which needs approval" refused:adapter.approval_required github tools/call \
			'{"name":"merge_pull_request","arguments":{"owner":"octo-org","repo":"demo","pullNumber":1}}'
	else
		skip "github pack (install github-mcp-server with integrations/agentgateway/install.sh)"
	fi

	echo "postgres pack"
	if postgres_enabled && docker container inspect "$PG_CONTAINER" >/dev/null 2>&1; then
		open_session postgres
		expect "SELECT" allowed postgres tools/call \
			'{"name":"execute_sql","arguments":{"sql":"SELECT customer, total FROM public.orders ORDER BY id"}}'
		expect "DELETE" refused:postgres.write_not_allowed postgres tools/call \
			'{"name":"execute_sql","arguments":{"sql":"DELETE FROM public.orders"}}'
		expect "escape a read-only transaction" refused:postgres.multiple_statements postgres tools/call \
			'{"name":"execute_sql","arguments":{"sql":"COMMIT; DROP TABLE public.orders"}}'
		expect "read a file through a function" refused:postgres.blocked_function postgres tools/call \
			"{\"name\":\"execute_sql\",\"arguments\":{\"sql\":\"SELECT pg_read_file('/etc/passwd')\"}}"
		expect "read a denied schema" refused:postgres.denied_schema postgres tools/call \
			'{"name":"execute_sql","arguments":{"sql":"SELECT * FROM secrets.api_keys"}}'
		expect "EXPLAIN ANALYZE, which runs the statement" refused:postgres.explain_analyze postgres tools/call \
			'{"name":"execute_sql","arguments":{"sql":"EXPLAIN ANALYZE DELETE FROM public.orders"}}'
		verify "  ...and every order is still there" order_count_is_3
	else
		skip "postgres pack (needs Docker)"
	fi

	echo "Failure handling"
	stop_pid opa
	sleep 1
	expect "OPA is down: the call is refused, not forwarded" http:403 filesystem tools/call \
		"{\"name\":\"write_file\",\"arguments\":{\"path\":\"$ws/projects/app/tmp/while-opa-down.txt\",\"content\":\"x\"}}"
	verify "  ...and nothing was written" test ! -e "$ws/projects/app/tmp/while-opa-down.txt"
	start_opa

	echo
	echo "$passed passed, $failed failed, $skipped skipped"
	[ "$failed" = 0 ]
}

case ${1:-all} in
up) up ;;
check) check ;;
down) down ;;
all)
	trap down EXIT
	up
	check
	;;
*)
	echo "usage: $0 [up|check|down]" >&2
	exit 2
	;;
esac
