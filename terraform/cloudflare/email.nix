{ lib, ... }:
let
  inherit (import ./records.nix) zoneId zones;

  accountId = "d73a984743f8be9a3de0aed322e5f005";
  inbox = "rathiharivansh@gmail.com";

  domains = {
    sh = {
      zone = zoneId;
      name = "harivan.sh";
    };
    cafe = {
      zone = zones.cafe;
      name = "hari.cafe";
    };
  };
  locals = [
    "hari"
    "me"
  ];

  rules = lib.listToAttrs (
    lib.concatMap (
      d:
      map (
        local:
        lib.nameValuePair "${d}_${local}" {
          zone_id = domains.${d}.zone;
          name = "${local}@${domains.${d}.name}";
          enabled = true;
          matchers = [
            {
              type = "literal";
              field = "to";
              value = "${local}@${domains.${d}.name}";
            }
          ];
          actions = [
            {
              type = "forward";
              value = [ inbox ];
            }
          ];
          depends_on = [ "cloudflare_email_routing_address.inbox" ];
        }
      ) locals
    ) (lib.attrNames domains)
  );
in
{
  resource.cloudflare_email_routing_dns = lib.mapAttrs (_: d: { zone_id = d.zone; }) domains;

  resource.cloudflare_email_routing_address.inbox = {
    account_id = accountId;
    email = inbox;
  };

  resource.cloudflare_email_routing_rule = rules;
}
