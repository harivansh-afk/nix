#!/usr/bin/env bash
# Headless check of dots/nvim/lua/pr: every module loads, the fast list marks
# and persists, and the shared keys are on the buffers. Offline - the forge
# and git are stubbed inside the assertions.
#
# Those live at dots/nvim/tests/pr-smoke.lua rather than under scripts/, so
# they inherit dots/nvim/.stylua.toml and the existing stylua check formats
# them with the rest of the config.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# -u NONE keeps the user's init out, and rtp^= puts THIS checkout ahead of
# ~/.config/nvim, which is a symlink to the live dots on a real machine and
# would otherwise answer the requires.
HOME="$work/home" \
  XDG_STATE_HOME="$work/state" \
  XDG_DATA_HOME="$work/data" \
  XDG_CACHE_HOME="$work/cache" \
  nvim --headless -u NONE -i NONE \
  -c "let mapleader=' '" \
  -c "set rtp^=$REPO_ROOT/dots/nvim" \
  -c "lua _G.map = function(mode, lhs, rhs, opts) vim.keymap.set(mode, lhs, rhs, vim.tbl_extend('keep', opts or {}, { silent = true })) end" \
  -c "luafile $REPO_ROOT/dots/nvim/tests/pr-smoke.lua" \
  </dev/null
