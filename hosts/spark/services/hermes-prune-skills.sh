#!/usr/bin/env bash
set -euo pipefail

skills_dir=$1
managed_skills=$2

for skill in "$skills_dir"/*; do
  [ -L "$skill" ] || continue
  name=${skill##*/}
  case "$(readlink -- "$skill")" in
  /nix/store/*-hermes-managed-skills/"$name")
    if [ ! -e "$managed_skills/$name" ]; then
      rm -- "$skill"
    fi
    ;;
  esac
done
