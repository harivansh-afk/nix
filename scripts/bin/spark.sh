# Opens a shell on spark over mosh (`--ssh` forces ssh -t for UDP-hostile
# networks). Plain `ssh spark`, scp, and git are untouched; this is the
# deliberate "console" entry point.

transport="mosh"

usage() {
  echo "usage: spark [--ssh]" >&2
  exit 2
}

for arg in "$@"; do
  case "$arg" in
  --ssh) transport="ssh" ;;
  *) usage ;;
  esac
done

if [ "$transport" = "mosh" ]; then
  exec mosh spark
fi
exec ssh -t spark
