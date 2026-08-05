#!/usr/bin/env bash
# Regenerate dots/nvim/pack-sources.json from dots/nvim/nvim-pack-lock.json.
#
# vim.pack owns the lock and rewrites it on every plugin change, so the nix
# hashes cannot live there. This mirrors each locked rev into a file nix can
# read, and lib/nvim-pack.nix refuses to evaluate when the two disagree.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
lock="$root/dots/nvim/nvim-pack-lock.json"
out="$root/dots/nvim/pack-sources.json"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

printf '{\n' >"$tmp"
first=1
for name in $(jq -r '.plugins | keys[]' "$lock"); do
  url=$(jq -r --arg n "$name" '.plugins[$n].src' "$lock")
  rev=$(jq -r --arg n "$name" '.plugins[$n].rev' "$lock")

  echo "prefetching $name @ ${rev:0:12}" >&2
  hash=$(nix-prefetch-git --url "$url" --rev "$rev" --quiet | jq -r '.hash')
  if [ -z "$hash" ] || [ "$hash" = "null" ]; then
    echo "failed to prefetch $name from $url at $rev" >&2
    exit 1
  fi

  [ $first -eq 1 ] || printf ',\n' >>"$tmp"
  first=0
  printf '  "%s": {\n    "hash": "%s",\n    "rev": "%s",\n    "url": "%s"\n  }' \
    "$name" "$hash" "$rev" "$url" >>"$tmp"
done
printf '\n}\n' >>"$tmp"

jq -S '.' "$tmp" >"$out"
echo "wrote $out ($(jq 'keys | length' "$out") plugins)" >&2
