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
  sparkDeploy = pkgs.writeShellApplication {
    name = "spark-deploy";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      flake="$1"
      unit="spark-deploy-$(date +%s)"
      status=0
      systemd-run --unit="$unit" --wait --collect --quiet \
        --setenv=SUDO_UID="''${SUDO_UID:?run spark-deploy through sudo}" \
        --setenv=PATH=/run/wrappers/bin:/run/current-system/sw/bin \
        --property=TimeoutStartSec=40min \
        /run/current-system/sw/bin/nixos-rebuild switch --flake "$flake#spark" || status=$?
      journalctl --unit="$unit" --output=cat --no-pager
      exit "$status"
    '';
  };

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
  repoUnits = "repo.code,repo.releases,repo.issues,repo.pulls,repo.wiki,repo.projects,repo.packages";
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

  pierreForgejo = inputs.pierrejo.lib.mkPierreForgejo { inherit pkgs; };
  forgejoWeb = import ./web.nix {
    inherit
      forgejoDomain
      forgejoPackage
      lib
      pierreForgejo
      pkgs
      ;
  };
  forgejoPackageBase = pkgs.callPackage (import "${pkgs.path}/pkgs/by-name/fo/forgejo/generic.nix" {
    version = "16.0.6";
    hash = "sha256-629cbLUh+okT3SFHwHFQDPiOoao0hrTxOzdOKxYEd6Q=";
    npmDepsHash = "sha256-C/ht4Z3ivtm6nBNHUkNmKpLsnmnrpzW6rBq153LuITc=";
    vendorHash = "sha256-wOAbZ6eEwlavMIcTOmqPpdgLNcgylCX4MwxuI/35YZw=";
    lts = false;
  }) { };
  forgejoPackage = pierreForgejo.mkForgejoWithPierre (
    forgejoPackageBase.overrideAttrs (old: {
      patches = [
        "${pkgs.path}/pkgs/by-name/fo/forgejo/static-root-path.patch"
      ];

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
    pierreForgejo.nixosModule
  ];

  services.caddy.virtualHosts."http://${forgejoDomain}" =
    lib.recursiveUpdate (loopbackVhost backendPort)
      {
        extraConfig = ''
          encode zstd gzip

          @forgejoAssets path /assets/* /manifest.json /favicon.svg /favicon.png /apple-touch-icon.png
          header @forgejoAssets Cache-Control "public, max-age=21600"

          handle_path /assets/fonts/* {
            root * /srv/harivan.sh/dist/fonts
            header Cache-Control "public, max-age=31536000, immutable"
            file_server
          }

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

  security.pam.services.sshd.rules.session.forgejo-systemd = {
    order = config.security.pam.services.sshd.rules.session.systemd.order - 1;
    control = "[success=1 default=ignore]";
    modulePath = "${pkgs.pam}/lib/security/pam_succeed_if.so";
    args = [
      "quiet"
      "user"
      "="
      "git"
    ];
  };

  systemd.services.forgejo.restartTriggers = [
    forgejoWeb.public
    forgejoWeb.templates
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
      "git.timeout".MIRROR = 1800;
      server = {
        DOMAIN = forgejoDomain;
        ROOT_URL = "https://${forgejoDomain}/";
        HTTP_PORT = backendPort;
        SSH_DOMAIN = forgejoDomain;
        LANDING_PAGE = "/harivansh-afk";
      };
      service = {
        REGISTER_EMAIL_CONFIRM = true;
        SEND_NOTIFICATION_EMAIL_ON_NEW_USER = true;
      };
      repository = {
        DEFAULT_PRIVATE = "private";

        DEFAULT_REPO_UNITS = repoUnits;
        DEFAULT_FORK_REPO_UNITS = repoUnits;
        DEFAULT_MIRROR_REPO_UNITS = repoUnits;
        DEFAULT_TEMPLATE_REPO_UNITS = repoUnits;
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
        DEFAULT_ACTIONS_URL = "https://github.com";
      };
      "cron.cleanup_offline_runners" = {
        ENABLED = true;
        RUN_AT_START = true;
        GLOBAL_SCOPE_ONLY = false;
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
        ENABLE_FEDERATED_AVATAR = true;
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
    environment.GIT_HTTP_LOW_SPEED_TIME = "600";
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

  environment.systemPackages = [ sparkDeploy ];

  security.sudo.extraRules = [
    {
      users = [ "gitea-runner" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/spark-deploy";
          options = [ "NOPASSWD" ];
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

    "L+ /var/lib/forgejo/.gitconfig - - - - /var/lib/forgejo/data/home/.gitconfig"

    "L+ /var/lib/forgejo/custom/public - - - - ${forgejoWeb.public}"
    "L+ /var/lib/forgejo/custom/templates - - - - ${forgejoWeb.templates}"
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
          dir = "${runnerCacheRoot}/actcache";
        };
      };
    };
  };
}
