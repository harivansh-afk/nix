# Per-remote connector, instantiated once per entry in lib/remotes.nix.
# Runs the remote's mux launcher (per-project nvim servers) over mosh. An
# optional project argument is resolved on the remote against `mux list`
# (live/stopped sessions + zoxide dirs), so `@NAME@ ix` jumps straight into
# the remote's `ix` project. Plain `ssh @HOST@`, scp, and git are untouched;
# this is the deliberate "console" entry point.

transport="mosh"
target=""
for arg in "$@"; do
  case "$arg" in
  --ssh) transport="ssh" ;;
  -*)
    echo "usage: @NAME@ [--ssh] [project]" >&2
    exit 2
    ;;
  *) target="$arg" ;;
  esac
done

if [ "$transport" = "mosh" ]; then
  if [ -n "$target" ]; then
    exec mosh "@HOST@" -- mux "$target"
  fi
  exec mosh "@HOST@" -- mux
fi
if [ -n "$target" ]; then
  exec ssh -t "@HOST@" mux "$target"
fi
exec ssh -t "@HOST@" mux
