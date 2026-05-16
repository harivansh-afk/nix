{
  config,
  pkgs,
  lib,
  ...
}:
let
  pushMirrors = {
    "harivansh-afk/.tmux" = "ssh://github.com/harivansh-afk/.tmux.git";
    "harivansh-afk/agentcomputer-delegate" =
      "ssh://github.com/harivansh-afk/agentcomputer-delegate.git";
    "harivansh-afk/agentikube" = "ssh://github.com/harivansh-afk/agentikube.git";
    "harivansh-afk/ai-dev-framework-2.0" = "ssh://github.com/harivansh-afk/AI-dev-framework-2.0.git";
    "harivansh-afk/ai-image-editor" = "ssh://github.com/harivansh-afk/AI-image-editor.git";
    "harivansh-afk/ai-scripts" = "ssh://github.com/harivansh-afk/ai-scripts.git";
    "harivansh-afk/ainas" = "ssh://github.com/harivansh-afk/aiNAS.git";
    "harivansh-afk/asap.it" = "ssh://github.com/harivansh-afk/asap.it.git";
    "harivansh-afk/austens-wedding-guide" = "ssh://github.com/harivansh-afk/Austens-Wedding-Guide.git";
    "harivansh-afk/auto-review-check" = "ssh://github.com/harivansh-afk/auto-review-check.git";
    "harivansh-afk/auto-school" = "ssh://github.com/harivansh-afk/auto-school.git";
    "harivansh-afk/befreed" = "ssh://github.com/harivansh-afk/befreed.git";
    "harivansh-afk/berkeley-mono-" = "ssh://github.com/harivansh-afk/berkeley-mono-.git";
    "harivansh-afk/better" = "ssh://github.com/harivansh-afk/better.git";
    "harivansh-afk/betternas" = "ssh://github.com/harivansh-afk/betterNAS.git";
    "harivansh-afk/blendify-vibes" = "ssh://github.com/harivansh-afk/blendify-vibes.git";
    "harivansh-afk/clank-artifacts" = "ssh://github.com/harivansh-afk/clank-artifacts.git";
    "harivansh-afk/clanker-agent" = "ssh://github.com/harivansh-afk/clanker-agent.git";
    "harivansh-afk/claude-code-vertical" = "ssh://github.com/harivansh-afk/claude-code-vertical.git";
    "harivansh-afk/claude-continual-learning" =
      "ssh://github.com/harivansh-afk/claude-continual-learning.git";
    "harivansh-afk/claude-setup" = "ssh://github.com/harivansh-afk/claude-setup.git";
    "harivansh-afk/clawd" = "ssh://github.com/harivansh-afk/clawd.git";
    "harivansh-afk/clawd-stack" = "ssh://github.com/harivansh-afk/clawd-stack.git";
    "harivansh-afk/co-mono" = "ssh://github.com/harivansh-afk/co-mono.git";
    "harivansh-afk/college" = "ssh://github.com/harivansh-afk/college.git";
    "harivansh-afk/computer-runtime" = "ssh://github.com/harivansh-afk/computer-runtime.git";
    "harivansh-afk/config" = "ssh://github.com/harivansh-afk/config.git";
    "harivansh-afk/cozybox.nvim" = "ssh://github.com/harivansh-afk/cozybox.nvim.git";
    "harivansh-afk/cryptocurrencypredictionlstm" =
      "ssh://github.com/harivansh-afk/CryptoCurrencyPredictionLSTM.git";
    "harivansh-afk/delphi-internal-dash" = "ssh://github.com/harivansh-afk/delphi-internal-dash.git";
    "harivansh-afk/delta" = "ssh://github.com/harivansh-afk/delta.git";
    "harivansh-afk/deskctl" = "ssh://github.com/harivansh-afk/deskctl.git";
    "harivansh-afk/diffkit" = "ssh://github.com/harivansh-afk/diffkit.git";
    "harivansh-afk/distributed-systems" = "ssh://github.com/harivansh-afk/distributed-systems.git";
    "harivansh-afk/dotfiles" = "ssh://github.com/harivansh-afk/dotfiles.git";
    "harivansh-afk/dots" = "ssh://github.com/harivansh-afk/dots.git";
    "harivansh-afk/dungeon" = "ssh://github.com/harivansh-afk/dungeon.git";
    "harivansh-afk/einstein" = "ssh://github.com/harivansh-afk/einstein.git";
    "harivansh-afk/emails" = "ssh://github.com/harivansh-afk/emails.git";
    "harivansh-afk/estateai" = "ssh://github.com/harivansh-afk/EstateAI.git";
    "harivansh-afk/eval-skill" = "ssh://github.com/harivansh-afk/eval-skill.git";
    "harivansh-afk/evaluclaude-harness" = "ssh://github.com/harivansh-afk/evaluclaude-harness.git";
    "harivansh-afk/fireplexity" = "ssh://github.com/harivansh-afk/fireplexity.git";
    "harivansh-afk/forge.nvim" = "ssh://github.com/harivansh-afk/forge.nvim.git";
    "harivansh-afk/gmv" = "ssh://github.com/harivansh-afk/gmv.git";
    "harivansh-afk/gobank" = "ssh://github.com/harivansh-afk/gobank.git";
    "harivansh-afk/gtmark" = "ssh://github.com/harivansh-afk/gtmark.git";
    "harivansh-afk/gymsupps" = "ssh://github.com/harivansh-afk/GymSupps.git";
    "harivansh-afk/habit-tracker" = "ssh://github.com/harivansh-afk/Habit-Tracker.git";
    "harivansh-afk/hari-data-pipeline" = "ssh://github.com/harivansh-afk/hari-data-pipeline.git";
    "harivansh-afk/harivansh-afk" = "ssh://github.com/harivansh-afk/harivansh-afk.git";
    "harivansh-afk/interview-coder" = "ssh://github.com/harivansh-afk/interview-coder.git";
    "harivansh-afk/ix" = "ssh://github.com/harivansh-afk/ix.git";
    "harivansh-afk/kubasync" = "ssh://github.com/harivansh-afk/kubasync.git";
    "harivansh-afk/llm-scripts" = "ssh://github.com/harivansh-afk/llm-scripts.git";
    "harivansh-afk/mixbridge-ios" = "ssh://github.com/harivansh-afk/mixbridge-ios.git";
    "harivansh-afk/mixbridge-web" = "ssh://github.com/harivansh-afk/mixbridge-web.git";
    "harivansh-afk/mixwithclaude" = "ssh://github.com/harivansh-afk/mixwithclaude.git";
    "harivansh-afk/nix" = "ssh://github.com/harivansh-afk/nix.git";
    "harivansh-afk/nvim" = "ssh://github.com/harivansh-afk/nvim.git";
    "harivansh-afk/nvim-wiki" = "ssh://github.com/harivansh-afk/nvim-wiki.git";
    "harivansh-afk/personalwebsite" = "ssh://github.com/harivansh-afk/PersonalWebsite.git";
    "harivansh-afk/phia-interior-dash" = "ssh://github.com/harivansh-afk/phia-interior-dash.git";
    "harivansh-afk/phinsta" = "ssh://github.com/harivansh-afk/phinsta.git";
    "harivansh-afk/pi-telegram-webhook" = "ssh://github.com/harivansh-afk/pi-telegram-webhook.git";
    "harivansh-afk/project-files" = "ssh://github.com/harivansh-afk/project-files.git";
    "harivansh-afk/rag-ui" = "ssh://github.com/harivansh-afk/RAG-ui.git";
    "harivansh-afk/ralph-cli" = "ssh://github.com/harivansh-afk/ralph-cli.git";
    "harivansh-afk/react-portfolio" = "ssh://github.com/harivansh-afk/React-Portfolio.git";
    "harivansh-afk/resume-website" = "ssh://github.com/harivansh-afk/Resume-website.git";
    "harivansh-afk/rpi" = "ssh://github.com/harivansh-afk/rpi.git";
    "harivansh-afk/rpi-artifacts" = "ssh://github.com/harivansh-afk/rpi-artifacts.git";
    "harivansh-afk/sep" = "ssh://github.com/harivansh-afk/sep.git";
    "harivansh-afk/solvex" = "ssh://github.com/harivansh-afk/Solvex.git";
    "harivansh-afk/supplmen" = "ssh://github.com/harivansh-afk/SupplMen.git";
    "harivansh-afk/system-design" = "ssh://github.com/harivansh-afk/system-design.git";
    "harivansh-afk/the-truman-project" = "ssh://github.com/harivansh-afk/The-Truman-Project.git";
    "harivansh-afk/theburnouts" = "ssh://github.com/harivansh-afk/theburnouts.git";
    "harivansh-afk/thread-view" = "ssh://github.com/harivansh-afk/thread-view.git";
    "harivansh-afk/thread-view-data" = "ssh://github.com/harivansh-afk/thread-view-data.git";
    "harivansh-afk/tmux-subagents" = "ssh://github.com/harivansh-afk/tmux-subagents.git";
    "harivansh-afk/tmux-wiki" = "ssh://github.com/harivansh-afk/tmux-wiki.git";
    "harivansh-afk/truman-backend" = "ssh://github.com/harivansh-afk/truman-backend.git";
    "harivansh-afk/twylo" = "ssh://github.com/harivansh-afk/Twylo.git";
    "harivansh-afk/twylo-backend" = "ssh://github.com/harivansh-afk/twylo-backend.git";
    "harivansh-afk/url-shortner" = "ssh://github.com/harivansh-afk/url-shortner.git";
    "harivansh-afk/veet-code" = "ssh://github.com/harivansh-afk/veet-code.git";
    "harivansh-afk/website" = "ssh://github.com/harivansh-afk/website.git";
    "harivansh-afk/x-cli" = "ssh://github.com/harivansh-afk/X-CLI.git";
    "harivansh-afk/youtube-posting" = "ssh://github.com/harivansh-afk/youtube-posting.git";
    "harivansh-afk/ytdlp-api" = "ssh://github.com/harivansh-afk/ytdlp-api.git";
  };

  noMirror = [
    "harivansh-afk/cp.nvim"
    "harivansh-afk/oil.nvim"
    "harivansh-afk/sandbox-agent"
  ];

  pullMirrorOwners = [
    "agentcomputerai"
    "atlas-agents"
    "charliemeyer2000"
    "dueflow-co"
    "getcompanion-ai"
    "indexable-inc"
    "parkerrex"
    "vibe-with-ai"
  ];

  actionsEnabledRepos = [
    "harivansh-afk/nix"
    "harivansh-afk/deskctl"
    "harivansh-afk/betternas"
    "harivansh-afk/agentikube"
  ];

  manifest = {
    schema = "forgejo-mirror-manifest/v1";
    forgejo_host = "git.harivan.sh";
    push_mirror_interval = "15m0s";
    push_mirror_sync_on_commit = true;
    pull_mirror_interval = "15m";
    push_mirrors = pushMirrors;
    no_mirror = noMirror;
    pull_mirror_owners = pullMirrorOwners;
    actions_enabled_repos = actionsEnabledRepos;
  };

  manifestJson = pkgs.writeText "forgejo-mirror-manifest.json" (builtins.toJSON manifest);
in
{
  environment.etc."forgejo-mirror/manifest.json".source = manifestJson;

  # Expose the manifest path as an env var so the scripts find it without
  # hardcoding (and so it survives a rename later).
  environment.variables.FORGEJO_MIRROR_MANIFEST = "/etc/forgejo-mirror/manifest.json";
}
