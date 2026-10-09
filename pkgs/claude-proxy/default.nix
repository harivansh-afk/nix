{
  lib,
  callPackage,
  formats,
  openssh,
  python3,
  replaceVars,
  writeShellApplication,
}:
let
  upstream = callPackage ./upstream.nix { };
  settings = (formats.json { }).generate "claude-proxy-settings.json" {
    config-version = 8;
    server = {
      host = "127.0.0.1";
      port = 18473;
      commercial-mode = true;
      discovery.enabled = false;
    };
    management = {
      allow-remote = false;
      secret-key = "";
      disable-control-panel = true;
      disable-auto-update-panel = true;
    };
    routing = {
      strategy = "round-robin";
      session-affinity = true;
      session-affinity-ttl = "24h";
      session-affinity-subagents = true;
      retry = {
        request-retry = 0;
        max-retry-credentials = 2;
        max-retry-interval = 5;
      };
      cooldown = {
        disable-cooling = false;
        save-cooldown-status = true;
      };
    };
    requests = {
      passthrough-headers = true;
      streaming = {
        keepalive-seconds = 15;
        bootstrap-retries = 0;
      };
    };
    observability = {
      logs = {
        debug = false;
        logging-to-file = false;
        request-log = false;
      };
      usage.usage-statistics-enabled = false;
      pprof.enable = false;
    };
    plugins.enabled = false;
  };
  script = replaceVars ./claude-proxy.py {
    inherit settings;
    upstream = lib.getExe upstream;
  };
in
writeShellApplication {
  name = "claude-proxy";
  runtimeInputs = [ openssh ];
  text = ''
    exec ${lib.getExe python3} ${script} "$@"
  '';
  passthru = { inherit upstream settings; };
  meta.description = "Private Claude account proxy and client launcher";
}
