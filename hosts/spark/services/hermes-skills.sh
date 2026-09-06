set -euo pipefail

hermes_home=$1
backup_root=$2
backup_dir=

shopt -s nullglob dotglob
for entry in "$hermes_home/skills/"*; do
  if [[ ! -d "$entry" && ! -L "$entry" && "${entry##*/}" != SKILL.md ]]; then
    continue
  fi
  if [[ -z "$backup_dir" ]]; then
    mkdir -p "$backup_root"
    chmod 700 "$backup_root"
    backup_dir=$(mktemp -d "$backup_root/migration.XXXXXXXX")
  fi
  mv -- "$entry" "$backup_dir/"
done

if [[ -n "$backup_dir" ]]; then
  echo "Archived runtime Hermes skills to $backup_dir; Nix supplies skills.external_dirs"
fi
