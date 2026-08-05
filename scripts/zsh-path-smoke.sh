#!/usr/bin/env bash
# Property: dots/zsh/zshrc must never put a system bin directory ahead of the
# nix profiles in $path.
#
# The regression this defends: the path array contained an unguarded
# "$(npm prefix -g 2>/dev/null)/bin". On a box where npm is not on PATH by the
# time .zshrc runs, the substitution is empty and the element becomes "/bin".
# zsh keeps it, /bin lands ahead of /etc/profiles/per-user/$USER/bin, and every
# nix-installed tool is shadowed by whatever the base image put in /bin. In the
# ix dev VM that silently swapped neovim for the platform's own wrapped build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'zsh path smoke: %s\n' "$1" >&2
  exit 1
}

# A HOME with the real zshrc and nothing else, so the only PATH writer under
# test is the path array itself.
home="$work/home"
mkdir -p "$home"
cp "$REPO_ROOT/dots/zsh/zshrc" "$home/.zshrc"

# `zsh -d` below skips /etc/zprofile and /etc/zshrc. Without it macOS runs
# path_helper, which injects /usr/local/bin and friends and would trip the
# assertion for a reason that has nothing to do with this repo.
#
# zshrc calls these unconditionally. Stub them so the shell reaches the path
# block instead of dying, and deliberately do NOT provide npm: absent npm is
# exactly the condition that produced the bug.
stubs="$work/stubs"
mkdir -p "$stubs"
for tool in zoxide direnv; do
  printf '#!/bin/sh\nexit 0\n' >"$stubs/$tool"
  chmod +x "$stubs/$tool"
done

# Force the failing condition rather than depending on the host not having npm.
# A PATH stub is not enough: macOS /etc/zshenv runs path_helper, which prepends
# the system dirs and finds the real npm first. A function wins over PATH lookup
# on every host, so this reproduces identically on a dev mac with node
# installed and on a CI box without it.
printf 'npm() { return 1; }\n' >"$home/.zshenv"

command -v zsh >/dev/null 2>&1 || fail "zsh not on PATH"
zsh_bin="$(command -v zsh)"

observed="$(
  env -i \
    HOME="$home" \
    ZDOTDIR="$home" \
    USER=smoke \
    TERM=dumb \
    PATH="$stubs:$(dirname "$zsh_bin")" \
    "$zsh_bin" -d -ic 'print -l $path' 2>/dev/null
)"

[ -n "$observed" ] || fail "interactive zsh produced no \$path"

# Inherited system dirs at the tail are fine and unavoidable. What must never
# happen is one of them overtaking the nix profile, which is what an empty
# element in the path array causes.
index_of() {
  printf '%s\n' "$observed" | grep -nxF "$1" | head -1 | cut -d: -f1
}

profile_at="$(index_of "/etc/profiles/per-user/smoke/bin")"
[ -n "$profile_at" ] || fail "/etc/profiles/per-user/smoke/bin missing from \$path entirely"

for sysdir in /bin /usr/bin /usr/local/bin /sbin /usr/sbin; do
  at="$(index_of "$sysdir")"
  [ -n "$at" ] || continue
  if [ "$at" -lt "$profile_at" ]; then
    fail "$sysdir is at position $at, ahead of the nix profile at $profile_at; an empty element in the path array collapsed to a system dir and now shadows every nix-installed tool"
  fi
done

printf 'zsh path smoke: ok (nix profile at position %s, ahead of every system dir)\n' "$profile_at"
