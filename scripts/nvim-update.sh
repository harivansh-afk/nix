#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
sources="$root/dots/nvim/pack-sources.json"
name=${1:?Usage: nvim-update.sh plugin [revision]}
url=$(jq -er --arg name "$name" '.[$name].url' "$sources")
rev=${2:-$(jq -r --arg name "$name" '.[$name].branch // "HEAD"' "$sources")}

source=$(nix-prefetch-git --url "$url" --rev "$rev" --quiet)
tmp=$(mktemp "$sources.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq --arg name "$name" --argjson source "$source" \
  '.[$name] += ($source | {rev, hash})' "$sources" >"$tmp"
mv "$tmp" "$sources"
