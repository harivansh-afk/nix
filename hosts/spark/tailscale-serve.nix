{
  pkgs,
  ...
}:
let
  tsHost = "spark-ix.tail368802.ts.net";
  serveConfig = {
    TCP."443".HTTPS = true;
    Web."${tsHost}:443".Handlers = {
      "/".Proxy = "http://127.0.0.1:4040";
      "/playbooks/".Proxy = "http://127.0.0.1:4060";
    };
  };
in
{
  services.tailscale.serve = {
    enable = true;
    configFile = (pkgs.formats.json { }).generate "tailscale-serve.json" serveConfig;
  };
}
