{
  config,
  inputs,
  lib,
  loopbackVhost,
  pkgs,
  ...
}:
let
  rootDomain = "harivan.sh";
  forgejoDomain = "git.${rootDomain}";
  backendPort = 19300;
  gitCredentialFile = "/var/lib/forgejo/.git-credentials";
  smtpPasswordFile = config.sops.secrets."forgejo-smtp-password".path;
  mirrorEnvFile = config.sops.secrets."forgejo-mirror.env".path;
  mirrorGithubTokenFile = config.sops.secrets."forgejo-mirror-github-token.env".path;
  runnerTokenFile = config.sops.secrets."forgejo-runner-token".path;
  runnerCacheRoot = "/var/cache/forgejo-runner";

  forgejoOauthSources = {
    github = {
      provider = "github";
      secretName = "forgejo-github-oauth.env";
      clientIdVariable = "GITHUB_OAUTH_CLIENT_ID";
      clientSecretVariable = "GITHUB_OAUTH_CLIENT_SECRET";
    };

    google = {
      provider = "gplus";
      secretName = "forgejo-google-oauth.env";
      clientIdVariable = "GOOGLE_OAUTH_CLIENT_ID";
      clientSecretVariable = "GOOGLE_OAUTH_CLIENT_SECRET";
    };
  };

  forgejoOauthSourceList = lib.mapAttrsToList (
    name: source: source // { inherit name; }
  ) forgejoOauthSources;

  forgejoOauthCredentials = lib.listToAttrs (
    map (source: {
      name = "oauth-${source.name}";
      value = config.sops.secrets.${source.secretName}.path;
    }) forgejoOauthSourceList
  );

  oauthSources = lib.concatMapStringsSep "\n" (
    source:
    lib.concatStringsSep ":" [
      source.name
      source.provider
      "oauth-${source.name}"
      source.clientIdVariable
      source.clientSecretVariable
    ]
  ) forgejoOauthSourceList;

  forgejoDb = "/var/lib/forgejo/data/forgejo.db";
  mirrorIntervalSeconds = 15 * 60;

  actionsEnforce = pkgs.writeShellScript "forgejo-actions-enforce" ''
    export PATH=${lib.makeBinPath [ pkgs.curl ]}
    export FORGEJO_API="https://${forgejoDomain}/api/v1"
    export FORGEJO_MIRROR_MANIFEST=/etc/forgejo-mirror/manifest.json
    export FORGEJO_DB=${forgejoDb}
    exec ${pkgs.python3}/bin/python3 ${./actions-enforce.py}
  '';

  normalizeMirrorSchedule = pkgs.writeShellScript "forgejo-normalize-mirror-schedule" ''
    export FORGEJO_DB=${forgejoDb}
    export MIRROR_INTERVAL_SECONDS=${toString mirrorIntervalSeconds}
    exec ${pkgs.python3}/bin/python3 ${./normalize-mirror-schedule.py}
  '';

  forgejoIconSvg = ./icon.svg;
  forgejoBrandingAssets =
    pkgs.runCommand "forgejo-branding-assets"
      {
        nativeBuildInputs = [ pkgs.librsvg ];
      }
      ''
        mkdir -p $out
        cp ${forgejoIconSvg} $out/favicon.svg
        cp ${forgejoIconSvg} $out/logo.svg
        rsvg-convert -w 192 -h 192 ${forgejoIconSvg} > $out/favicon.png
        rsvg-convert -w 180 -h 180 ${forgejoIconSvg} > $out/apple-touch-icon.png
        rsvg-convert -w 512 -h 512 ${forgejoIconSvg} > $out/logo.png
      '';

  mkForgejoAuthMail =
    args: pkgs.replaceVars ./mail-auth.tmpl.in ({ domain = forgejoDomain; } // args);

  forgejoMailActivateTmpl = mkForgejoAuthMail {
    title = "Welcome to ${forgejoDomain}";
    heading = "Welcome to ${forgejoDomain}";
    urlExpr = ''printf "%suser/activate?code=%s" AppUrl (QueryEscape .Code)'';
    buttonLabel = "Confirm your account";
    codeLivesVar = ".ActiveCodeLives";
  };

  forgejoMailResetPasswdTmpl = mkForgejoAuthMail {
    title = "Reset your password";
    heading = "Reset your password";
    urlExpr = ''printf "%suser/recover_account?code=%s" AppUrl (QueryEscape .Code)'';
    buttonLabel = "Reset password";
    codeLivesVar = ".ResetPwdCodeLives";
  };

  forgejoMailActivateEmailTmpl = mkForgejoAuthMail {
    title = "Confirm your new email";
    heading = "Confirm your new email";
    urlExpr = ''printf "%suser/activate_email?code=%s&email=%s" AppUrl (QueryEscape .Code) (QueryEscape .Email)'';
    buttonLabel = "Confirm email";
    codeLivesVar = ".ActiveCodeLives";
  };
  pierreForgejo = inputs.pierrejo.lib.mkPierreForgejo { inherit pkgs; };
  forgejoWeb = import ./web.nix {
    inherit
      forgejoPackage
      lib
      pierreForgejo
      pkgs
      ;
  };
  forgejoPackageBase = pkgs.callPackage (import "${pkgs.path}/pkgs/by-name/fo/forgejo/generic.nix" {
    version = "16.0.3";
    hash = "sha256-G2kp2k/ivqxXG68+piBczXujtj3f/fLr+DnHoiMKOB4=";
    npmDepsHash = "sha256-QwZ8X0pVxs5u4jMOqy3VGcBGVqqDKpLCMPmwoECVwEg=";
    vendorHash = "sha256-0nvMy0oyVIy2qBngg1eu0UAGBEuoCGzDdsBYUuU/A48=";
    lts = false;
  }) { };
  forgejoPackage = pierreForgejo.mkForgejoWithPierre (
    forgejoPackageBase.overrideAttrs (old: {
      patches = [
        "${pkgs.path}/pkgs/by-name/fo/forgejo/static-root-path.patch"
      ];
      # Forgejo 16 git hooks use "#!/usr/bin/env" shebangs, absent in the
      # sandbox; nixpkgs master's generic.nix fixes, until the pin catches up.
      preCheck = (old.preCheck or "") + ''
        substituteInPlace modules/git/hook_generate.go \
          --replace-fail "#!/usr/bin/env" "#!${pkgs.lib.getExe' pkgs.coreutils "env"}"
      '';
      checkFlags = [
        "-skip=^TestPassword$|^TestCaptcha$|^TestDNSUpdate$|^TestMigrateRepository$|^TestMigrateWhiteBlocklist$|^TestURLAllowedSSH/Pushmirror_URL$|^TestBleveDeleteIssue$"
      ];
    })
  );
in
{
  imports = [
    ./mirror-manifest.nix
    ./mirror-forge.nix
    pierreForgejo.nixosModule
  ];

  services.caddy.virtualHosts."http://${forgejoDomain}" =
    lib.recursiveUpdate (loopbackVhost backendPort)
      {
        extraConfig = ''
          encode zstd gzip

          @forgejoAssets path /assets/* /manifest.json /favicon.svg /favicon.png /apple-touch-icon.png
          header @forgejoAssets Cache-Control "public, max-age=21600"

          @forgejoFonts path /assets/fonts/*
          header @forgejoFonts Cache-Control "public, max-age=31536000, immutable"

          reverse_proxy 127.0.0.1:${toString backendPort}
        '';
      };

  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };
  users.groups.git = { };

  # Forgejo parses templates once at startup.
  systemd.services.forgejo.restartTriggers = [
    forgejoWeb.frontend
    forgejoWeb.js
    forgejoWeb.templates
    forgejoWeb.assets
    pierreForgejo.frontend
    pierreForgejo.assets
    pierreForgejo.templates
  ];

  systemd.services.forgejo.preStart = lib.mkAfter ''
    export PATH=${
      lib.makeBinPath [
        pkgs.git
        pkgs.gawk
      ]
    }:$PATH
    export GITHUB_TOKEN_FILE=${mirrorGithubTokenFile}
    export GIT_CREDENTIAL_FILE=${gitCredentialFile}
    export FORGEJO=${config.services.forgejo.package}/bin/forgejo
    export OAUTH_SOURCES=${lib.escapeShellArg oauthSources}
    ${pkgs.bash}/bin/bash ${./pre-start.sh}
  '';

  services.forgejo = {
    enable = true;
    package = forgejoPackage;
    user = "git";
    group = "git";
    secrets.mailer.PASSWD = smtpPasswordFile;
    settings = {
      server = {
        DOMAIN = forgejoDomain;
        ROOT_URL = "https://${forgejoDomain}/";
        HTTP_PORT = backendPort;
        SSH_DOMAIN = forgejoDomain;
        LANDING_PAGE = "/harivansh-afk";
      };
      service = {
        DISABLE_REGISTRATION = false;
        REQUIRE_SIGNIN_VIEW = false;
        DEFAULT_USER_IS_RESTRICTED = false;
        REGISTER_EMAIL_CONFIRM = true;
        SEND_NOTIFICATION_EMAIL_ON_NEW_USER = true;
      };
      repository = {
        DEFAULT_PRIVATE = "private";
        DEFAULT_PUSH_CREATE_PRIVATE = true;
        # Only mirror-manifest.actions_enabled_repos opt back in (see
        # forgejo-actions-enforce below).
        DEFAULT_REPO_UNITS = "repo.code,repo.releases,repo.issues,repo.pulls,repo.wiki,repo.projects,repo.packages";
        DEFAULT_FORK_REPO_UNITS = "repo.code,repo.releases,repo.issues,repo.pulls,repo.wiki,repo.projects,repo.packages";
        DEFAULT_MIRROR_REPO_UNITS = "repo.code,repo.releases,repo.issues,repo.pulls,repo.wiki,repo.projects,repo.packages";
        DEFAULT_TEMPLATE_REPO_UNITS = "repo.code,repo.releases,repo.issues,repo.pulls,repo.wiki,repo.projects,repo.packages";
      };
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtps";
        SMTP_ADDR = "smtp.resend.com";
        SMTP_PORT = 465;
        USER = "resend";
        FROM = "Forgejo <git@${rootDomain}>";
      };
      session.COOKIE_SECURE = true;
      database = {
        SQLITE_JOURNAL_MODE = "WAL";
        SQLITE_TIMEOUT = 10000;
      };
      mirror = {
        DEFAULT_INTERVAL = "15m";
        MIN_INTERVAL = "5m";
      };
      "queue.mirror" = {
        MAX_WORKERS = 1;
      };
      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "https://github.com";
      };
      "cron.cleanup_offline_runners" = {
        ENABLED = true;
        RUN_AT_START = true;
        SCHEDULE = "@midnight";
        GLOBAL_SCOPE_ONLY = false;
        OLDER_THAN = "24h";
      };
      "git.config" = {
        "credential.helper" = "store --file ${gitCredentialFile}";
      };
      "repository.signing" = {
        FORMAT = "ssh";
        SIGNING_KEY = "/var/lib/forgejo/signing/id_ed25519.pub";
        SIGNING_NAME = "Forgejo";
        SIGNING_EMAIL = "git@${rootDomain}";
        MERGES = "always";
      };
      ui = {
        DEFAULT_THEME = "cozybox-auto";
        THEMES = "cozybox-auto,cozybox-light,cozybox-dark,forgejo-auto,forgejo-dark,forgejo-light";
      };
      picture = {
        DISABLE_GRAVATAR = false;
        ENABLE_FEDERATED_AVATAR = true;
        GRAVATAR_SOURCE = "gravatar";
      };
      oauth2_client = {
        UPDATE_AVATAR = true;
      };
      "ui.meta" = {
        AUTHOR = forgejoDomain;
        DESCRIPTION = "Personal code, experiments, and project history.";
        KEYWORDS = "git,code,harivansh,rathi,nix";
      };
      other = {
        SHOW_FOOTER_VERSION = false;
        SHOW_FOOTER_TEMPLATE_LOAD_TIME = false;
        SHOW_FOOTER_LICENSES_API = false;
        SHOW_FOOTER_POWERED_BY = false;
      };
      api = {
        ENABLE_SWAGGER = false;
      };
    };
  };

  services.pierre-ssr.enable = true;

  systemd.services.forgejo = {
    after = [ "pierre-ssr.service" ];
    wants = [ "pierre-ssr.service" ];
    serviceConfig.Environment = [
      "PIERRE_FILE_TREE=true"
      "PIERRE_SSR_SOCKET=${config.services.pierre-ssr.socketPath}"
    ];
  };

  systemd.services.forgejo.serviceConfig.ExecStartPre = lib.mkBefore [
    (pkgs.writeShellScript "forgejo-signing-key" ''
      if [ ! -f /var/lib/forgejo/signing/id_ed25519 ]; then
        mkdir -p /var/lib/forgejo/signing
        chmod 700 /var/lib/forgejo/signing
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" \
          -C "forgejo@${rootDomain}" -f /var/lib/forgejo/signing/id_ed25519
      fi
    '')
    normalizeMirrorSchedule
  ];
  systemd.services.forgejo.serviceConfig.LoadCredential = lib.mkAfter (
    lib.mapAttrsToList (name: path: "${name}:${path}") forgejoOauthCredentials
  );

  # Actions are off for every repo except mirror-manifest.actions_enabled_repos;
  # this re-clamps newly migrated mirrors before they can run anything.
  systemd.services.forgejo-actions-enforce = {
    description = "Force Actions on/off per mirror-manifest allowlist";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [ mirrorEnvFile ];
      ExecStart = actionsEnforce;
    };
  };
  systemd.timers.forgejo-actions-enforce = {
    description = "Periodic Actions allowlist enforcement";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "30min";
      AccuracySec = "30s";
      Unit = "forgejo-actions-enforce.service";
    };
  };

  systemd.services.gitea-runner-spark = {
    restartIfChanged = false;
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "gitea-runner";
      Group = lib.mkForce "gitea-runner";
      NoNewPrivileges = lib.mkForce false;
      RestrictSUIDSGID = lib.mkForce false;
    };
  };

  users.users.gitea-runner = {
    isSystemUser = true;
    group = "gitea-runner";
    home = "/var/lib/gitea-runner";
    createHome = true;
  };
  users.groups.gitea-runner = { };

  security.sudo.extraRules = [
    {
      users = [ "gitea-runner" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
      ];
    }
  ];

  systemd.tmpfiles.rules = [
    "d ${runnerCacheRoot} 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/cargo 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/npm 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/pip 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/pre-commit 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/rustup 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/uv 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/actcache 0750 gitea-runner gitea-runner -"

    # git runs with HOME=/var/lib/forgejo but the rendered gitconfig (with
    # the credential helper) lands under data/home.
    "L+ /var/lib/forgejo/.gitconfig - - - - /var/lib/forgejo/data/home/.gitconfig"

    "d /var/lib/forgejo/custom 0750 git git -"
    "d /var/lib/forgejo/custom/public 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets/css 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets/fonts 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets/img 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/css/harivan-forgejo.css - - - - ${forgejoWeb.assets}/css/harivan-forgejo.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/pierre-forgejo.css - - - - ${pierreForgejo.assets}/css/pierre-forgejo.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-cozybox-auto.css - - - - ${forgejoWeb.assets}/css/theme-cozybox-auto.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-cozybox-light.css - - - - ${forgejoWeb.assets}/css/theme-cozybox-light.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-cozybox-dark.css - - - - ${forgejoWeb.assets}/css/theme-cozybox-dark.css"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/BerkeleyMono-Regular.otf - - - - /srv/harivan.sh/dist/fonts/BerkeleyMono-Regular.otf"
    "L+ /var/lib/forgejo/custom/public/assets/js - - - - ${forgejoWeb.js}/js"
    "L+ /var/lib/forgejo/custom/public/assets/img/favicon.svg - - - - ${forgejoBrandingAssets}/favicon.svg"
    "L+ /var/lib/forgejo/custom/public/assets/img/favicon.png - - - - ${forgejoBrandingAssets}/favicon.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/logo.svg - - - - ${forgejoBrandingAssets}/logo.svg"
    "L+ /var/lib/forgejo/custom/public/assets/img/logo.png - - - - ${forgejoBrandingAssets}/logo.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/apple-touch-icon.png - - - - ${forgejoBrandingAssets}/apple-touch-icon.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/avatar_default.png - - - - ${forgejoPackage.data}/public/assets/img/avatar_default.png"

    "d /var/lib/forgejo/custom/templates 0750 git git -"
    "d /var/lib/forgejo/custom/templates/custom 0750 git git -"
    "d /var/lib/forgejo/custom/templates/repo 0750 git git -"
    "d /var/lib/forgejo/custom/templates/repo/diff 0750 git git -"
    "d /var/lib/forgejo/custom/templates/mail 0750 git git -"
    "d /var/lib/forgejo/custom/templates/mail/auth 0750 git git -"
    "L+ /var/lib/forgejo/custom/templates/custom/header.tmpl - - - - ${forgejoWeb.templates}/custom/header.tmpl"
    "L+ /var/lib/forgejo/custom/templates/custom/footer.tmpl - - - - ${forgejoWeb.templates}/custom/footer.tmpl"
    "L+ /var/lib/forgejo/custom/templates/repo/commit_header.tmpl - - - - ${forgejoWeb.templates}/repo/commit_header.tmpl"
    "L+ /var/lib/forgejo/custom/templates/repo/diff/box.tmpl - - - - ${pierreForgejo.templates}/repo/diff/box.tmpl"
    "L+ /var/lib/forgejo/custom/templates/repo/shabox_badge.tmpl - - - - ${forgejoWeb.templates}/repo/shabox_badge.tmpl"
    "L+ /var/lib/forgejo/custom/templates/repo/view_file.tmpl - - - - ${forgejoWeb.templates}/repo/view_file.tmpl"
    "L+ /var/lib/forgejo/custom/templates/mail/auth/activate.tmpl - - - - ${forgejoMailActivateTmpl}"
    "L+ /var/lib/forgejo/custom/templates/mail/auth/reset_passwd.tmpl - - - - ${forgejoMailResetPasswdTmpl}"
    "L+ /var/lib/forgejo/custom/templates/mail/auth/activate_email.tmpl - - - - ${forgejoMailActivateEmailTmpl}"
  ];

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;

    instances.spark = {
      enable = true;
      name = "spark";
      url = "https://${forgejoDomain}";
      tokenFile = runnerTokenFile;

      labels = [
        "native:host"
        "spark:host"
        "ubuntu-latest:docker://node:24-bookworm"
      ];

      hostPackages = with pkgs; [
        bash
        coreutils
        curl
        fd
        gh
        git
        gnumake
        gnused
        gnutar
        gzip
        gawk
        jq
        nix
        nixos-rebuild
        nodejs_24
        pkg-config
        pnpm
        python3
        python3Packages.pip
        ripgrep
        rustup
        stdenv.cc
        unzip
        uv
        wget
        xvfb-run
        xz
        zip
      ];

      settings = {
        log.level = "info";
        runner = {
          capacity = 2;
          timeout = "3h";
          envs = {
            CARGO_HOME = "${runnerCacheRoot}/cargo";
            PIP_CACHE_DIR = "${runnerCacheRoot}/pip";
            PRE_COMMIT_HOME = "${runnerCacheRoot}/pre-commit";
            RUSTUP_HOME = "${runnerCacheRoot}/rustup";
            UV_CACHE_DIR = "${runnerCacheRoot}/uv";
            npm_config_cache = "${runnerCacheRoot}/npm";
          };
        };
        cache = {
          enabled = true;
          dir = "${runnerCacheRoot}/actcache";
        };
      };
    };
  };
}
