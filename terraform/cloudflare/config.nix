{ lib, ... }:
let
  inventory = import ./records.nix;
  inherit (inventory) zoneId records;

  mkRecord =
    _: r:
    {
      zone_id = zoneId;
      inherit (r) name type;
      ttl = r.ttl or 1;
    }
    // lib.optionalAttrs (r ? content) { inherit (r) content; }
    // lib.optionalAttrs (r ? data) { inherit (r) data; }
    // lib.optionalAttrs (r ? proxied) { inherit (r) proxied; }
    // lib.optionalAttrs (r ? priority) { inherit (r) priority; }
    // lib.optionalAttrs (r ? comment) { inherit (r) comment; }
    // lib.optionalAttrs (r ? tags) { inherit (r) tags; };
in
{
  terraform = {
    required_providers.cloudflare = {
      source = "cloudflare/cloudflare";
      version = "~> 5";
    };
    backend.local.path = "state/terraform.tfstate";
  };

  provider.cloudflare = { };

  resource.cloudflare_dns_record = lib.mapAttrs mkRecord records;
}
