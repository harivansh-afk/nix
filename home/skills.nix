{
  config,
  lib,
  pkgs,
  ...
}:
let
  globalSkills = [
    {
      name = "rams";
      source = "https://github.com/brianlovin/claude-config";
    }
    {
      name = "agent-browser";
      source = "https://github.com/vercel-labs/agent-browser";
    }
    {
      name = "find-skills";
      source = "https://github.com/vercel-labs/skills";
    }
    {
      name = "frontend-design";
      source = "https://github.com/anthropics/skills";
    }
    {
      name = "next-best-practices";
      source = "https://github.com/vercel-labs/next-skills";
    }
    {
      name = "turborepo";
      source = "https://github.com/vercel/turborepo";
    }
    {
      name = "tmux";
      source = "https://github.com/harivansh-afk/tmux-subagents";
    }
  ];

  manifestHash = builtins.hashString "sha256" (builtins.toJSON globalSkills);

  installCommands = lib.concatMapStringsSep "\n" (skill: ''
    "${pkgs.nodejs_22}/bin/npx" skills add ${lib.escapeShellArg skill.source} --skill ${lib.escapeShellArg skill.name} -g -y
  '') globalSkills;

  missingChecks = lib.concatMapStringsSep "\n" (skill: ''
    if [ ! -e "$HOME/.agents/skills/${skill.name}" ]; then
      needs_sync=1
    fi
  '') globalSkills;
in
{
  home.activation.ensureGlobalSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state_dir="${config.xdg.stateHome}/skills"
    stamp_file="$state_dir/global-skills-manifest.sha256"
    desired_hash=${lib.escapeShellArg manifestHash}
    needs_sync=0

    mkdir -p "$state_dir" "$HOME/.agents/skills"

    if [ ! -f "$stamp_file" ] || [ "$(cat "$stamp_file")" != "$desired_hash" ]; then
      needs_sync=1
    fi

    ${missingChecks}

    if [ "$needs_sync" -eq 1 ]; then
      export PATH="${
        lib.makeBinPath [
          pkgs.nodejs_22
          pkgs.git
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnused
        ]
      }:$PATH"

      ${installCommands}

      printf '%s\n' "$desired_hash" > "$stamp_file"
    fi
  '';
}
