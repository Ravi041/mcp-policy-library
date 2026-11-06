#!/bin/sh
# Install the binaries the agentgateway walkthrough uses into .bin/, verifying each download
# against integrations/agentgateway/tools.sha256:
#
#   agentgateway       the MCP gateway
#   opa-envoy          OPA built with the Envoy ext_authz gRPC plugin, which agentgateway calls
#   github-mcp-server  optional; only the GitHub part of the walkthrough needs it
#
# None of these are needed to build, lint or test the library itself.
set -eu

AGENTGATEWAY_VERSION="v1.7.0"
OPA_ENVOY_VERSION="v1.22.0-envoy"
GITHUB_MCP_SERVER_VERSION="v2.1.0"

here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH='' cd -- "$here/../.." && pwd)"
bin="$root/.bin"
mkdir -p "$bin"

case "$(uname -s)/$(uname -m)" in
Darwin/arm64) agw=darwin-arm64 envoy=darwin_arm64 gh=Darwin_arm64 ;;
Linux/x86_64 | Linux/amd64) agw=linux-amd64 envoy=linux_amd64 gh=Linux_x86_64 ;;
Linux/aarch64 | Linux/arm64) agw=linux-arm64 envoy=linux_arm64 gh=Linux_arm64 ;;
*)
	echo "unsupported platform: $(uname -s)/$(uname -m); agentgateway publishes macOS arm64 and Linux builds" >&2
	exit 1
	;;
esac

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

# download <asset> <url> <file>: fetch and verify against the pinned checksum.
download() {
	expected="$(awk -v a="$1" '$2 == a {print $1}' "$here/tools.sha256")"
	if [ -z "$expected" ]; then
		echo "no pinned checksum for $1 in tools.sha256" >&2
		exit 1
	fi
	curl -fsSL -o "$3" "$2"
	actual="$(sha256 "$3")"
	if [ "$actual" != "$expected" ]; then
		rm -f "$3"
		echo "checksum mismatch for $1: expected $expected, got $actual" >&2
		exit 1
	fi
}

install_binary() {
	name="$1" asset="$2" url="$3"
	if [ -x "$bin/$name" ] && [ "$(sha256 "$bin/$name")" = "$(awk -v a="$asset" '$2 == a {print $1}' "$here/tools.sha256")" ]; then
		echo "$name already installed"
		return 0
	fi
	download "$asset" "$url" "$bin/$name.download"
	chmod +x "$bin/$name.download"
	mv "$bin/$name.download" "$bin/$name"
	echo "installed $name ($asset)"
}

install_binary agentgateway "agentgateway-$agw" \
	"https://github.com/agentgateway/agentgateway/releases/download/$AGENTGATEWAY_VERSION/agentgateway-$agw"
install_binary opa-envoy "opa_envoy_${envoy}_static" \
	"https://github.com/open-policy-agent/opa-envoy-plugin/releases/download/$OPA_ENVOY_VERSION/opa_envoy_${envoy}_static"

if [ "${WITH_GITHUB:-1}" = 1 ]; then
	archive="github-mcp-server_$gh.tar.gz"
	if [ -x "$bin/github-mcp-server" ] && "$bin/github-mcp-server" --version 2>/dev/null | grep -q "Version: ${GITHUB_MCP_SERVER_VERSION#v}$"; then
		echo "github-mcp-server already installed"
	else
		download "$archive" \
			"https://github.com/github/github-mcp-server/releases/download/$GITHUB_MCP_SERVER_VERSION/$archive" \
			"$bin/$archive"
		tar -xzf "$bin/$archive" -C "$bin" github-mcp-server
		rm -f "$bin/$archive"
		echo "installed github-mcp-server ($archive)"
	fi
fi
