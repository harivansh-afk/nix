# Per-remote connector, instantiated once per entry in lib/remotes.nix.
# Runs the remote's mux launcher (per-project nvim servers) over mosh. Plain
# `ssh @HOST@`, scp, and git are untouched; this is the deliberate "console"
# entry point.

transport="mosh"
for arg in "$@"; do
  case "$arg" in
  --ssh) transport="ssh" ;;
  *)
    echo "usage: @NAME@ [--ssh]" >&2
    exit 2
    ;;
  esac
done

if [ "$transport" = "mosh" ]; then
  exec mosh "@HOST@" -- mux
fi
exec ssh -t "@HOST@" mux
