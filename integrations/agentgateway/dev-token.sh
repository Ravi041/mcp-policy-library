#!/bin/sh
# Development-only identity for trying the adapter locally.
#
#   dev-token.sh keys <dir>           create <dir>/dev-key.pem and <dir>/jwks.json
#   dev-token.sh token <dir> <sub>    print an RS256 token for <sub>, valid for one hour
#
# The gateway verifies tokens against jwks.json, and the adapter reads the verified
# `sub` claim as principal.id. Never use these keys outside a local test.
# Needs only openssl and xxd.
set -eu

ISSUER=mcp-policy-library-dev
AUDIENCE=mcp-gateway

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

case ${1:-} in
keys)
	dir=$2
	mkdir -p "$dir"
	openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$dir/dev-key.pem" 2>/dev/null
	chmod 600 "$dir/dev-key.pem"
	n=$(openssl rsa -in "$dir/dev-key.pem" -noout -modulus | sed 's/^Modulus=//' | xxd -r -p | b64url)
	printf '{"keys":[{"kty":"RSA","use":"sig","alg":"RS256","kid":"dev","n":"%s","e":"AQAB"}]}\n' "$n" > "$dir/jwks.json"
	;;
token)
	dir=$2 sub=$3
	now=$(date +%s)
	header=$(printf '{"alg":"RS256","typ":"JWT","kid":"dev"}' | b64url)
	payload=$(printf '{"iss":"%s","aud":"%s","sub":"%s","iat":%s,"exp":%s}' \
		"$ISSUER" "$AUDIENCE" "$sub" "$now" "$((now + 3600))" | b64url)
	sig=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$dir/dev-key.pem" -binary | b64url)
	printf '%s.%s.%s\n' "$header" "$payload" "$sig"
	;;
*)
	echo "usage: $0 keys <dir> | token <dir> <sub>" >&2
	exit 2
	;;
esac
