{ lib, ... }:
let
  inherit (import ./records.nix) zoneId zones;

  allZones = {
    sh = zoneId;
  }
  // zones;

  forgejoExpensive = [
    "/archive/"
    "/blame/"
    "/commit/"
    "/commits/"
    "/compare/"
  ];
  pathMatch = lib.concatMapStringsSep " or " (
    p: ''http.request.uri.path contains "${p}"''
  ) forgejoExpensive;

  searchableHosts = [
    "harivan.sh"
    "www.harivan.sh"
    "hari.cafe"
    "www.hari.cafe"
  ];
  searchBotCategories = [
    "Search Engine Crawler"
    "Search Engine Optimization"
    "Archiver"
  ];
  quoted = l: lib.concatMapStringsSep " " (v: ''"${v}"'') l;

  searchBotRule = {
    ref = "search_bots_private_hosts";
    description = "Keep search crawlers off everything but the public sites";
    expression = "(cf.verified_bot_category in {${quoted searchBotCategories}} and not http.host in {${quoted searchableHosts}})";
    action = "block";
    enabled = true;
  };
in
{
  resource.cloudflare_bot_management = lib.mapAttrs (_: id: {
    zone_id = id;
    ai_bots_protection = "block";
    crawler_protection = "enabled";
    is_robots_txt_managed = true;
    enable_js = true;
    fight_mode = false;
  }) allZones;

  resource.cloudflare_ruleset.sh_custom_firewall = {
    zone_id = zoneId;
    name = "default";
    kind = "zone";
    phase = "http_request_firewall_custom";
    rules = [
      {
        ref = "forgejo_expensive_challenge";
        description = "Challenge Forgejo archive/blame/commit/compare pages";
        expression = ''(http.host eq "git.harivan.sh" and (${pathMatch}))'';
        action = "managed_challenge";
        enabled = true;
      }
      searchBotRule
    ];
  };

  resource.cloudflare_ruleset.cafe_custom_firewall = {
    zone_id = zones.cafe;
    name = "default";
    kind = "zone";
    phase = "http_request_firewall_custom";
    rules = [ searchBotRule ];
  };
}
