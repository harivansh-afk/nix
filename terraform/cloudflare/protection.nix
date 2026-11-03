{ lib, ... }:
let
  inherit (import ./records.nix) zoneId zones;

  allZones = {
    sh = zoneId;
  }
  // zones;

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
  resource.cloudflare_zone_setting = lib.mapAttrs' (
    name: id:
    lib.nameValuePair "${name}_always_https" {
      zone_id = id;
      setting_id = "always_use_https";
      value = "on";
    }
  ) allZones;

  resource.cloudflare_ruleset.sh_rate_limit = {
    zone_id = zoneId;
    name = "Request rate limit";
    kind = "zone";
    phase = "http_ratelimit";
    rules = [
      {
        ref = "request_burst_limit";
        description = "Limit bursts across public hosts on the free plan";
        expression = ''starts_with(http.request.uri.path, "/")'';
        action = "block";
        enabled = true;
        ratelimit = {
          characteristics = [
            "cf.colo.id"
            "ip.src"
          ];
          period = 10;
          requests_per_period = 100;
          mitigation_timeout = 10;
        };
      }
    ];
  };

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
