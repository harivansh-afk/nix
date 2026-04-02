{
  ...
}:
let
  sandboxDomain = "netty.harivan.sh";
  forgejoDomain = "git.harivan.sh";
  vaultDomain = "vault.harivan.sh";
  betternasDomain = "api.betternas.com";
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

    # Reserved for future use - nothing listening on this port yet
    virtualHosts.${sandboxDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:2470";
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

    virtualHosts.${betternasDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3100";
      locations."/dav/".proxyPass = "http://127.0.0.1:8090";
    };
  };
}
