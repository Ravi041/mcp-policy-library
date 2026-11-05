#!/bin/sh
# Install the pinned OPA and Regal binaries into .bin/, verifying each download
# against the checksums committed in scripts/tools.sha256.
set -eu

OPA_VERSION="v1.22.1"
REGAL_VERSION="v0.43.0"

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
bin="$root/.bin"
mkdir -p "$bin"

case "$(uname -s)" in
Darwin) opa_os=darwin regal_os=Darwin ;;
Linux) opa_os=linux regal_os=Linux ;;
*)
	echo "unsupported OS: $(uname -s)" >&2
	exit 1
	;;
esac

case "$(uname -m)" in
arm64 | aarch64) opa_arch=arm64 regal_arch=arm64 ;;
x86_64 | amd64) opa_arch=amd64 regal_arch=x86_64 ;;
*)
	echo "unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac

# OPA publishes no static build for Intel macOS.
if [ "$opa_os/$opa_arch" = "darwin/amd64" ]; then
	opa_asset="opa_darwin_amd64"
else
	opa_asset="opa_${opa_os}_${opa_arch}_static"
fi
regal_asset="regal_${regal_os}_${regal_arch}"

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

fetch() {
	name="$1"
	asset="$2"
	url="$3"
	expected="$(awk -v a="$asset" '$2 == a {print $1}' "$root/scripts/tools.sha256")"
	if [ -z "$expected" ]; then
		echo "no pinned checksum for $asset in scripts/tools.sha256" >&2
		exit 1
	fi
	if [ -x "$bin/$name" ] && [ "$(sha256 "$bin/$name")" = "$expected" ]; then
		echo "$name already installed"
		return 0
	fi
	tmp="$bin/$name.download"
	curl -fsSL -o "$tmp" "$url"
	actual="$(sha256 "$tmp")"
	if [ "$actual" != "$expected" ]; then
		rm -f "$tmp"
		echo "checksum mismatch for $asset: expected $expected, got $actual" >&2
		exit 1
	fi
	chmod +x "$tmp"
	mv "$tmp" "$bin/$name"
	echo "installed $name ($asset)"
}

fetch opa "$opa_asset" "https://github.com/open-policy-agent/opa/releases/download/$OPA_VERSION/$opa_asset"
fetch regal "$regal_asset" "https://github.com/open-policy-agent/regal/releases/download/$REGAL_VERSION/$regal_asset"
