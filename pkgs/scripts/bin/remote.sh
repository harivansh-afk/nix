# Per-remote connector, instantiated once per entry in lib/remotes.nix.
# Opens a shell on the remote over mosh (`--ssh` forces ssh -t for
# UDP-hostile networks). Plain `ssh @HOST@`, scp, and git are untouched;
# this is the deliberate "console" entry point.

transport="mosh"

usage() {
  echo "usage: @NAME@ [--ssh]" >&2
  exit 2
}

for arg in "$@"; do
  case "$arg" in
  --ssh) transport="ssh" ;;
  *) usage ;;
  esac
done

if [ "$transport" = "mosh" ]; then
  exec mosh "@HOST@"
fi
exec ssh -t "@HOST@"
