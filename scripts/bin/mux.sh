# Per-remote connector, instantiated once per entry in lib/remotes.nix.
# Attaches (or creates) the server's tmux session. Plain `ssh @HOST@`,
# scp, and git are untouched; this is the deliberate "console" entry point.

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
  exec mosh "@HOST@" -- tmux new-session -A -s "@SESSION@"
fi
exec ssh -t "@HOST@" tmux new-session -A -s "@SESSION@"
