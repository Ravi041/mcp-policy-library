#!/bin/sh
# Repository quality gates that formatting, linting and unit tests cannot see:
# the design principles, the contracts and pack completeness.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

failures=0
fail() {
	echo "FAIL: $1"
	failures=$((failures + 1))
}
pass() {
	echo "ok:   $1"
}

rego_sources() {
	find policies -name '*.rego' ! -name '*_test.rego'
}

# Schemas are well-formed JSON Schema documents on the draft OPA validates.
for schema in schemas/input.schema.json schemas/decision.schema.json; do
	if opa eval --fail --input "$schema" 'json.verify_schema(input)[0] == true; input["$schema"] == "http://json-schema.org/draft-07/schema#"' >/dev/null 2>&1; then
		pass "$schema is a valid draft-07 schema"
	else
		fail "$schema is not a valid draft-07 schema"
	fi
done

# Principle 1: policies never name a gateway or vendor.
if rego_sources | xargs grep -n -i -E 'kavrynt|envoy|istio|kong|apigee|traefik|portkey|litellm' >&2; then
	fail "policies must not reference a specific gateway or vendor"
else
	pass "policies name no gateway or vendor"
fi

# Principle 1: policies read only fields the input schema documents.
documented="$(opa eval --format=raw --input schemas/input.schema.json 'concat("|", object.keys(input.properties))')"
undocumented="$(rego_sources | xargs grep -h -o -E '\binput\.[a-zA-Z_]+' | sed 's/^input\.//' | sort -u | grep -v -E "^($documented)\$" || true)"
if [ -n "$undocumented" ]; then
	fail "policies read input fields missing from the schema: $undocumented"
else
	pass "policies read only documented input fields"
fi

# Principle 2: Rego is the only engine for now, in Rego v1 syntax.
if [ -n "$(find . -name '*.cedar' -not -path './.git/*')" ]; then
	fail "Cedar policies are out of scope for now"
else
	pass "no Cedar policies"
fi
if grep -r -n -E 'future\.keywords' policies >&2; then
	fail "use Rego v1 syntax, not future.keywords"
else
	pass "no deprecated Rego imports"
fi

# Principle 6: annotations are read only by the baseline deny rule.
if rego_sources | grep -v '^policies/mcp/packs/baseline/' | xargs grep -n 'annotations' >&2; then
	fail "only the baseline pack may read tool annotations"
else
	pass "annotations are read only by baseline"
fi

# `not f(input.x)` and `not input.x in y` are undefined when the field is missing, not true,
# so a check written this way silently passes. Assign the value or wrap it in a helper rule.
if rego_sources | xargs grep -n -E 'not [a-zA-Z_.]+\(.*input\.|not input\.[^ ]+ in ' >&2; then
	fail "negated check reads input directly and fails open when the field is missing"
else
	pass "no negated checks read input directly"
fi

# Every pack is complete, and is wired into the router and root README.
routable="$(opa eval --format=raw --data policies/ 'concat(" ", data.mcp.main.routable_packs)')"
for dir in packs/*/; do
	pack="$(basename "$dir")"
	for file in "policies/mcp/packs/$pack/policy.rego" "policies/mcp/packs/$pack/policy_test.rego" "packs/$pack/README.md" "packs/$pack/data.example.json"; do
		[ -f "$file" ] || fail "$pack is missing $file"
	done
	set -- "packs/$pack"/fixtures/allow_*.json
	[ -f "$1" ] || fail "$pack has no allow_ fixture"
	set -- "packs/$pack"/fixtures/deny_*.json
	[ -f "$1" ] || fail "$pack has no deny_ fixture"
	grep -q '^Verified against:' "packs/$pack/README.md" || fail "$pack README has no 'Verified against:' line"
	grep -q "packs/$pack" README.md || fail "root README does not link to the $pack pack"
	if [ "$pack" != baseline ]; then
		case " $routable " in
		*" $pack "*) ;;
		*) fail "$pack is not in routable_packs" ;;
		esac
	fi
	opa eval --fail --input "packs/$pack/data.example.json" 'object.keys(input) = {"mcp_config"}' >/dev/null 2>&1 ||
		fail "packs/$pack/data.example.json must hold only the mcp_config key"
	opa eval --fail --input "packs/$pack/data.example.json" --stdin 2>/dev/null <<Q >/dev/null || fail "packs/$pack/data.example.json has no mcp_config.$pack config"
input.mcp_config["$pack"]
Q

	# Principle 5: every deny code is documented in its pack's README.
	codes="$(awk '/lib\.deny_reason\($/ { getline; getline; print; next }
		/lib\.deny_reason\(/ { print }
		/"code": "/ { sub(/.*"code": "/, ""); sub(/".*/, ""); print "\"" $0 "\"" }' "policies/mcp/packs/$pack/policy.rego" |
		grep -o -E '"[a-z_]+"' | tr -d '"' | sort -u)"
	if [ -z "$codes" ]; then
		fail "found no deny codes in the $pack pack"
	fi
	for code in $codes; do
		grep -q "$pack\.$code" "packs/$pack/README.md" || fail "$pack.$code is not documented in packs/$pack/README.md"
	done
done
pass "checked pack completeness, routing and deny code documentation"

# Router and input-validation codes are documented in the decision model.
for code in $(grep -o -E '"main",[[:space:]]*$|deny_reason\("main", "[a-z_]+"' policies/mcp/main/main.rego | grep -o -E '"[a-z_]+"$' | tr -d '"'); do
	grep -q "main\.$code" docs/decision-model.md || fail "main.$code is not documented in docs/decision-model.md"
done
for code in $(awk '/"main",$/ { getline; print }' policies/mcp/main/main.rego | grep -o -E '"[a-z_]+"' | tr -d '"'); do
	grep -q "main\.$code" docs/decision-model.md || fail "main.$code is not documented in docs/decision-model.md"
done
pass "main deny codes are documented"

# Every CI action is pinned to a full commit SHA.
if grep -h -E '^\s*(- )?uses:' .github/workflows/*.yml | grep -v -E '@[0-9a-f]{40}( |$)' >&2; then
	fail "workflow actions must be pinned to a full commit SHA"
else
	pass "workflow actions are pinned by SHA"
fi

# The README stays plain ASCII, which also keeps emoji out.
if LC_ALL=C grep -n "$(printf '[\200-\377]')" README.md >&2; then
	fail "README.md must be plain ASCII"
else
	pass "README.md is plain ASCII"
fi

# Example decisions match the current policy version.
version="$(opa eval --format=raw --data policies/ 'data.mcp.main.policy_version')"
for decision in examples/*/decision.json; do
	[ -f "$decision" ] || continue
	opa eval --fail --input "$decision" "input.policy_version = \"$version\"" >/dev/null 2>&1 ||
		fail "$decision does not carry policy_version $version"
done
pass "example decisions carry policy_version $version"

# A release tag must match the policy version.
if [ -n "${RELEASE_TAG:-}" ] && [ "$RELEASE_TAG" != "v$version" ]; then
	fail "tag $RELEASE_TAG does not match policy_version $version"
fi

echo
echo "$failures QA failures"
[ "$failures" -eq 0 ]
