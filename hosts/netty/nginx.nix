{
  ...
}:
let
  hermesDomain = "netty.harivan.sh";
  forgejoDomain = "git.harivan.sh";
  vaultDomain = "vault.harivan.sh";
  betternasDomain = "api.betternas.com";
  diffkitDomain = "diffs.harivan.sh";
in
{
  security.acme = {
    acceptTerms = true;
    defaults.email = "rathiharivansh@gmail.com";
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "512m";

    virtualHosts.${hermesDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:2470";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header X-Forwarded-For $remote_addr;
        '';
      };
    };

    virtualHosts.${forgejoDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:19300";
    };

    virtualHosts.${vaultDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8222";
    };

    virtualHosts.${diffkitDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3200";
        proxyWebsockets = true;
      };
    };

    virtualHosts.${betternasDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3100";
      locations."/dav/".proxyPass = "http://127.0.0.1:8090";
    };
  };
}
