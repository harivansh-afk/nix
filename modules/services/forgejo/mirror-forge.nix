# Forge -> forgejo snapshot mirror for indexable-inc/ix.
#
# git.harivan.sh/indexable-inc/ix is a git SNAPSHOT MIRROR of the jj-native
# ix forge (forge.ix.dev). The forge speaks no git protocol (jj RPC on :8447,
# JSON UI API on :8448), so forgejo's built-in pull mirrors cannot track it.
# This timer materializes forge main through a dedicated jj-ix workspace and
# pushes "snapshot: forge main @ <rev>" commits into forgejo over localhost -
# the same commit shape as the manual 2026-08-13 snapshots it continues.
#
# Bootstrap state (created by hand 2026-08-16; the script assumes it exists
# and fails loudly if it does not, because recreating it is NOT automatable
# today - `jj-ix ix clone` is refused by the forge's protected-main gate):
#   ~rathi/.local/state/forge-snapshot/ws
#     jj-ix workspace "forgejo-mirror", registered via `jj-ix workspace add`
#     off the operator checkout at ~rathi/Documents/Git/indexable/ix
#     (.jj/repo is a relative pointer into that checkout - if the checkout
#     moves, re-register the workspace).
#   ~rathi/.local/state/forge-snapshot/git
#     plain git clone of the forgejo repo, main checked out.
#
# jj-ix is the operator's bootstrap binary (~/.local/bin/jj-ix), not a nix
# package: pkgs/jj-ix pins the archived GitHub mirror, which predates the
# forge server's current wire surface. Swap this to a nix-built client once
# one exists for the live server.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  stateDir = "/home/${username}/.local/state/forge-snapshot";
  jjIx = "/home/${username}/.local/bin/jj-ix";
  tokenFile = config.sops.secrets."forgejo-token.env".path;

  forgeSnapshotMirror = pkgs.writeShellApplication {
    name = "forge-snapshot-mirror";
    runtimeInputs = [
      pkgs.git
      pkgs.rsync
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail
      export HOME=/home/${username}

      ws="${stateDir}/ws"
      gitdir="${stateDir}/git"
      jj="${jjIx}"

      [ -e "$ws/.jj/repo" ] || { echo "missing jj workspace at $ws (see mirror-forge.nix bootstrap notes)"; exit 1; }
      [ -d "$gitdir/.git" ] || { echo "missing git clone at $gitdir"; exit 1; }

      # Current forge main tip (read-only; no working-copy op).
      tip=$("$jj" -R "$ws" --ignore-working-copy log -r main --no-graph \
        -T 'commit_id.short(12) ++ "\t" ++ change_id.short(12) ++ "\t" ++ description.first_line()')
      rev=$(printf '%s' "$tip" | cut -f1)
      change=$(printf '%s' "$tip" | cut -f2)

      # Forgejo auth for fetch and push: token as the basic-auth password,
      # read at runtime, never stored in the remote URL or on disk.
      TOK=$(cat ${tokenFile})
      export TOK
      # shellcheck disable=SC2016 # $TOK expands inside git's helper, not here
      authgit() { git -c credential.helper='!f() { echo username=harivansh-afk; echo "password=$TOK"; }; f' "$@"; }

      # Re-anchor the git clone on whatever forgejo currently serves, so a
      # foreign push or a crashed previous run cannot wedge this one.
      authgit -C "$gitdir" fetch -q origin main
      git -C "$gitdir" checkout -q main
      git -C "$gitdir" reset -q --hard origin/main

      subject="snapshot: forge main @ $rev (change $change)"
      last=$(git -C "$gitdir" log -1 --format=%s)
      if [ "$last" = "$subject" ]; then
        echo "up to date @ $rev"
        exit 0
      fi

      # Materialize main in the mirror workspace. Ops against the forge can
      # be refused transiently on op-head merge races ("main is protected"),
      # and the workspace can go stale when the operator checkout advances
      # the shared repo - retry through both.
      ok=0
      for attempt in 1 2 3; do
        if "$jj" -R "$ws" new main; then
          ok=1
          break
        fi
        echo "jj new main failed (attempt $attempt); trying update-stale + retry"
        "$jj" -R "$ws" workspace update-stale || true
        sleep 10
      done
      [ "$ok" = 1 ] || { echo "could not advance the mirror workspace to main"; exit 1; }

      # Snapshot exactly what got materialized (@-), not the tip we read
      # earlier - main may have advanced in between.
      tip=$("$jj" -R "$ws" --ignore-working-copy log -r '@-' --no-graph \
        -T 'commit_id.short(12) ++ "\t" ++ change_id.short(12) ++ "\t" ++ description.first_line()')
      rev=$(printf '%s' "$tip" | cut -f1)
      change=$(printf '%s' "$tip" | cut -f2)
      desc=$(printf '%s' "$tip" | cut -f3-)
      subject="snapshot: forge main @ $rev (change $change)"

      rsync -a --delete --exclude=/.jj --exclude=/.git "$ws/" "$gitdir/"

      cd "$gitdir"
      # -f: the forge tree carries files that are TRACKED in jj but match a
      # .gitignore somewhere above them (upstream view trees ship their own
      # ignores: nix ignores build/, ghostty/linux/mesa similar - 872 files
      # measured 2026-08-19). A bare `git add -A` silently drops those from
      # every snapshot, which shipped an incomplete tree to forgejo AND to the
      # index public mirror (nix-ix failed to build there: views/nix/src/
      # libstore/build/*.cc missing). Everything rsynced here came from the jj
      # materialization, so it is forge-tracked by construction; force-add all
      # of it.
      git add -A -f
      if git diff --cached --quiet; then
        echo "tree unchanged at $rev; nothing to push"
        exit 0
      fi

      git -c user.name='Harivansh Rathi' -c user.email='rathiharivansh@gmail.com' \
        commit -q -m "$subject" -m "Tree snapshot of the jj-native ix forge (SOT), taken from
      https://forge.ix.dev:8447/rpc repo ix.

      Forge commit: $rev (main)
      $desc"

      authgit push -q origin main
      echo "pushed $subject"
    '';
  };
in
{
  systemd.services.forge-snapshot-mirror = {
    description = "Snapshot forge.ix.dev main into forgejo indexable-inc/ix";
    after = [
      "forgejo.service"
      "network-online.target"
    ];
    requires = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      Group = "users";
      ExecStart = lib.getExe forgeSnapshotMirror;
      # Materializing 170k+ files can take a while on a cold cache, and
      # recovering from op-head divergence after killed runs re-fetches
      # hundreds of MB from the forge - killing at 45min restarted that
      # recovery from scratch every hour (2026-08-21 wedge). The hourly
      # timer coalesces triggers while a run is still activating, so a
      # long timeout only delays the next run, never stacks them.
      TimeoutStartSec = "3h";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.forge-snapshot-mirror = {
    description = "Hourly forge -> forgejo snapshot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "1h";
      AccuracySec = "5min";
      Unit = "forge-snapshot-mirror.service";
    };
  };
}
