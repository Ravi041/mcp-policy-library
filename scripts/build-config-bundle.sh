#!/bin/sh
# Build a config bundle (root: mcp_config) from data files that each hold
# {"mcp_config": {...}}. Defaults to every pack's data.example.json.
#
#   sh scripts/build-config-bundle.sh dist/config.tar.gz [data.json ...]
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

output="${1:-dist/config.tar.gz}"
[ "$#" -gt 0 ] && shift
if [ "$#" -eq 0 ]; then
	set -- packs/*/data.example.json
fi

work="$(mktemp -d)"
trap 'rm -r "$work"' EXIT

data_args=""
for file in "$@"; do
	data_args="$data_args --data $file"
done

mkdir -p "$work/mcp_config" "$(dirname "$output")"
# shellcheck disable=SC2086 # data_args is a list of flags
opa eval --format=raw $data_args 'data.mcp_config' >"$work/mcp_config/data.json"
printf '{"roots":["mcp_config"]}\n' >"$work/.manifest"
opa build --bundle "$work" --output "$output"
echo "wrote $output"
