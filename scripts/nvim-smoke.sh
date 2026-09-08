#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data"
export NVIM_APPNAME=nvim-portable
export XDG_STATE_HOME="$work/state" XDG_CACHE_HOME="$work/cache"
legacy="$XDG_DATA_HOME/$NVIM_APPNAME/site/pack/core/start/legacy/plugin"
mkdir -p "$legacy"
echo 'error("legacy plugin loaded")' >"$legacy/legacy.lua"

mkdir -p "$XDG_CONFIG_HOME/$NVIM_APPNAME/plugin"
echo 'error("legacy config loaded")' >"$XDG_CONFIG_HOME/$NVIM_APPNAME/plugin/legacy.lua"

for run in 1 2; do
	nvim --headless -i NONE -c "luafile $root/dots/nvim/tests/startup.lua" </dev/null
	test ! -e "$XDG_CONFIG_HOME/$NVIM_APPNAME/nvim-pack-lock.json"
	test ! -e "$XDG_DATA_HOME/$NVIM_APPNAME/site/pack/core/opt"
done

ln -s "$(command -v nvim)" "$work/view"
ln -s "$(command -v nvim)" "$work/vimdiff"
"$work/view" --headless -u NONE '+lua if not vim.o.readonly then vim.cmd.cquit() end' +qa
"$work/vimdiff" --headless -u NONE '+lua if not vim.wo.diff then vim.cmd.cquit() end' +qa
