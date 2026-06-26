_:
# hermes-wiki.nix - enable the Hermes "LLM Wiki" for the gateway.
#
# What this is
# -----------
# Hermes ships a bundled skill `research/llm-wiki` (Andrej Karpathy's LLM Wiki
# pattern): a self-improving, interlinked Markdown knowledge base the agent
# builds and maintains - entity/concept/comparison pages, `[[wikilinks]]`,
# contradiction flags, an `index.md` catalog and an append-only `log.md`. It is
# plain markdown on disk, so the same directory doubles as an Obsidian vault.
#
# Unlike RAG (which re-derives knowledge per query) the wiki compiles knowledge
# once and keeps it current: cross-references are already there, contradictions
# already flagged. The human curates sources and directs analysis; the agent
# summarizes, cross-references, files, and maintains consistency. That makes it
# a good fit alongside Hari's existing recall surfaces (`memory`, `kb-search`,
# `session_search`) - it is the agent-authored, durable synthesis layer those
# three lack.
#
# How the skill is enabled
# ------------------------
# Verified against the package source
# (/nix/store/*hermes-agent*/lib/python3.12/site-packages and
# share/hermes-agent/skills/research/llm-wiki/SKILL.md):
#
#   1. The skill is BUNDLED. The Nix wrapper for `hermes` already exports
#      HERMES_BUNDLED_SKILLS=<store>/share/hermes-agent/skills, and
#      tools/skills_sync.py seeds the bundled tree into ~/.hermes/skills/. The
#      `skills` toolset (enabled in hermes.nix's cliToolsets) surfaces it to the
#      model. So no extra install/seed step is needed.
#
#   2. The skill body reads ONE knob: the WIKI_PATH environment variable
#      (SKILL.md: `WIKI="${WIKI_PATH:-$HOME/wiki}"`). It is a plain shell env var
#      consumed by the skill's bash/recipes - there is no python config key for
#      it - so the only wiring required is putting WIKI_PATH into the gateway
#      process environment and making that directory exist.
#
# This module therefore does exactly two things, without touching hermes.nix:
#   - merges `WIKI_PATH` into systemd.services.hermes-gateway.environment
#     (NixOS attrset merge across modules - no edit to hermes.nix's environment
#     block needed), and
#   - creates the wiki directory (owned by rathi) via tmpfiles.
#
# Location
# --------
# /home/rathi/Documents/hermes-wiki - a real, browsable Obsidian vault under the
# user's home (matching the repo's /home/rathi/Documents convention), readable
# on the desktop/phone via Obsidian while the agent writes to it on spark. It is
# the agent's own knowledge store, deliberately separate from the kb-ingestion
# staging area (/var/lib/kb) which holds connector-pulled source data.
let
  user = "rathi";
  group = "users";
  home = "/home/${user}";
  wikiPath = "${home}/Documents/hermes-wiki";
in
{
  # Tell the bundled llm-wiki skill where the vault lives. This merges with the
  # `environment` attrset defined in hermes.nix rather than replacing it.
  systemd.services.hermes-gateway.environment.WIKI_PATH = wikiPath;

  # Create the vault directory, owned by rathi (the gateway runs as rathi, and
  # Obsidian on other devices reads/writes the same tree). The skill creates the
  # internal layout (SCHEMA.md, index.md, log.md, raw/, entities/, ...) on first
  # use; we only guarantee the top-level directory exists.
  systemd.tmpfiles.rules = [
    "d ${wikiPath} 0755 ${user} ${group} -"
  ];
}
