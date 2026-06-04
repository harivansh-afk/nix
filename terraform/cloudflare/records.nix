{
  zoneId = "c2fef6f61afd37613d77dc08ad6890b7";

  tunnel = "64bce32c-6613-459c-bb68-262d73e1b78f.cfargotunnel.com";

  records = {
    apex = {
      name = "harivan.sh";
      type = "CNAME";
      content = "64bce32c-6613-459c-bb68-262d73e1b78f.cfargotunnel.com";
      proxied = true;
      comment = "spark cloudflared tunnel";
    };
    www = {
      name = "www.harivan.sh";
      type = "CNAME";
      content = "64bce32c-6613-459c-bb68-262d73e1b78f.cfargotunnel.com";
      proxied = true;
      comment = "spark cloudflared tunnel";
    };
    git = {
      name = "git.harivan.sh";
      type = "CNAME";
      content = "64bce32c-6613-459c-bb68-262d73e1b78f.cfargotunnel.com";
      proxied = true;
      comment = "spark cloudflared tunnel";
    };
    vault = {
      name = "vault.harivan.sh";
      type = "CNAME";
      content = "64bce32c-6613-459c-bb68-262d73e1b78f.cfargotunnel.com";
      proxied = true;
      comment = "spark cloudflared tunnel";
    };
    delta = {
      name = "delta.harivan.sh";
      type = "CNAME";
      content = "64bce32c-6613-459c-bb68-262d73e1b78f.cfargotunnel.com";
      proxied = true;
      comment = "spark cloudflared tunnel";
    };
    parakeet = {
      name = "parakeet.harivan.sh";
      type = "CNAME";
      content = "64bce32c-6613-459c-bb68-262d73e1b78f.cfargotunnel.com";
      proxied = true;
    };
    status = {
      name = "status.harivan.sh";
      type = "CNAME";
      content = "statuspage.betteruptime.com";
      proxied = false;
      ttl = 3600;
    };

    caa_sectigo = {
      name = "harivan.sh";
      type = "CAA";
      data = {
        flags = 0;
        tag = "issue";
        value = "sectigo.com";
      };
    };
    caa_pkigoog = {
      name = "harivan.sh";
      type = "CAA";
      data = {
        flags = 0;
        tag = "issue";
        value = "pki.goog";
      };
    };
    caa_letsencrypt = {
      name = "harivan.sh";
      type = "CAA";
      data = {
        flags = 0;
        tag = "issue";
        value = "letsencrypt.org";
      };
    };

    mx_send = {
      name = "send.harivan.sh";
      type = "MX";
      content = "feedback-smtp.us-east-1.amazonses.com";
      priority = 10;
    };
    txt_spf_send = {
      name = "send.harivan.sh";
      type = "TXT";
      content = ''"v=spf1 include:amazonses.com ~all"'';
    };
    txt_dkim_resend = {
      name = "resend._domainkey.harivan.sh";
      type = "TXT";
      content = ''"p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDX1TsbsBSXUK0anX3yfVVrFqP0e1qCvFVnAlwqeRxFFENo1FzqewuDciyJQCmNBnwBJ/Xgfbbl62olYIHIgVzMzJryTJMiQEDponYGFyL2i+Wg84lXGC6AZIVIAm87os679k4jExE9LSea+sYRomFXmfol19ZvTUyiUagNwnahXwIDAQAB"'';
    };
    txt_dmarc = {
      name = "_dmarc.harivan.sh";
      type = "TXT";
      content = ''"v=DMARC1; p=none; rua=mailto:dmarc@harivan.sh"'';
    };
  };
}
