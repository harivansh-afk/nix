{
  config,
  lib,
  loopbackVhost,
  mkSparkSecret,
  pkgs,
  ...
}:
let
  rootDomain = "harivan.sh";
  forgejoDomain = "git.${rootDomain}";
  backendPort = 19300;
  forgejoApiUrl = "http://127.0.0.1:${toString backendPort}";
  gitCredentialFile = "/var/lib/forgejo/.git-credentials";
  smtpPasswordFile = config.sops.secrets."forgejo-smtp-password".path;
  mirrorEnvFile = config.sops.secrets."forgejo-mirror.env".path;
  runnerTokenFile = config.sops.secrets."forgejo-runner-token".path;
  runnerCacheRoot = "/var/cache/forgejo-runner";

  forgejoIconSvg = ./forgejo-icon.svg;
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
        rsvg-convert -w 1024 -h 1024 ${forgejoIconSvg} > $out/avatar_default.png
      '';

  forgejoCozyboxDarkCss = pkgs.writeText "theme-cozybox-dark.css" ''
    @import url("/assets/css/theme-forgejo-dark.css");

    :root {
      --is-dark-theme: true;
      color-scheme: dark;

      /* steel ladder remapped to cozybox dark bg->fg shades */
      --steel-900: #1d2021;
      --steel-850: #232425;
      --steel-800: #282828;
      --steel-750: #2c2a28;
      --steel-700: #32302f;
      --steel-650: #3c3836;
      --steel-600: #45403c;
      --steel-550: #504945;
      --steel-500: #5a544f;
      --steel-450: #665c54;
      --steel-400: #7c6f64;
      --steel-350: #928374;
      --steel-300: #a89984;
      --steel-250: #bdae93;
      --steel-200: #d5c4a1;
      --steel-150: #e1d5a8;
      --steel-100: #ebdbb2;

      /* surface / structure */
      --color-body:               #282828;
      --color-box-body:           #1d2021;
      --color-box-body-highlight: #32302f;
      --color-box-header:         #32302f;
      --color-header-wrapper:     #1d2021;
      --color-footer:             #1d2021;
      --color-nav-bg:             #1d2021;
      --color-nav-hover-bg:       #3c3836;
      --color-secondary-nav-bg:   #282828;
      --color-card:               #32302f;
      --color-menu:               #32302f;
      --color-button:             #504945;
      --color-hover:              #45403c;
      --color-active:             #3c3836;
      --color-timeline:           #504945;

      /* text */
      --color-text:             #ebdbb2;
      --color-text-dark:        #ffffff;
      --color-text-light:       #d5c4a1;
      --color-text-light-1:     #bdae93;
      --color-text-light-2:     #a89984;
      --color-text-light-3:     #928374;
      --color-placeholder-text: #928374;

      /* secondary */
      --color-secondary:           #504945;
      --color-secondary-bg:        #3c3836;
      --color-secondary-dark-1:    #5a544f;
      --color-secondary-dark-2:    #665c54;
      --color-secondary-light-1:   #45403c;
      --color-secondary-light-2:   #3c3836;
      --color-secondary-light-3:   #32302f;
      --color-secondary-light-4:   #282828;
      --color-secondary-alpha-10:  #5049451a;
      --color-secondary-alpha-20:  #50494533;
      --color-secondary-alpha-30:  #5049454d;
      --color-secondary-alpha-40:  #50494566;
      --color-secondary-alpha-50:  #50494580;
      --color-secondary-alpha-60:  #50494599;
      --color-secondary-alpha-70:  #504945b3;
      --color-secondary-alpha-80:  #504945cc;
      --color-secondary-alpha-90:  #504945e6;

      /* inputs */
      --color-input-background:   #1d2021;
      --color-input-text:         #ebdbb2;
      --color-input-border:       #504945;
      --color-input-border-hover: #665c54;
      --color-input-toggle-background: #32302f;

      /* links */
      --color-link:       #5b84de;
      --color-link-hover: #7596e8;

      /* primary -> cozybox blue (#5b84de) */
      --color-primary:          #5b84de;
      --color-primary-contrast: #ffffff;
      --color-primary-dark-1:   #6c91e3;
      --color-primary-dark-2:   #7e9de8;
      --color-primary-dark-3:   #91aaec;
      --color-primary-dark-4:   #a4b7f0;
      --color-primary-dark-5:   #b6c4f4;
      --color-primary-dark-6:   #c9d1f7;
      --color-primary-dark-7:   #dcdef9;
      --color-primary-light-1:  #4a73c8;
      --color-primary-light-2:  #3a62b3;
      --color-primary-light-3:  #2c519d;
      --color-primary-light-4:  #1f4287;
      --color-primary-light-5:  #143371;
      --color-primary-light-6:  #0a255c;
      --color-primary-light-7:  #021847;
      --color-primary-alpha-10: #5b84de1a;
      --color-primary-alpha-20: #5b84de33;
      --color-primary-alpha-30: #5b84de4d;
      --color-primary-alpha-40: #5b84de66;
      --color-primary-alpha-50: #5b84de80;
      --color-primary-alpha-60: #5b84de99;
      --color-primary-alpha-70: #5b84deb3;
      --color-primary-alpha-80: #5b84decc;
      --color-primary-alpha-90: #5b84dee6;
      --color-primary-hover:    var(--color-primary-light-1);
      --color-primary-active:   var(--color-primary-light-2);
      --color-accent:           #5b84de;

      /* cozybox dark accents */
      --color-red:    #ea6962;
      --color-orange: #fe8019;
      --color-yellow: #d8a657;
      --color-olive:  #b8bb26;
      --color-green:  #a9b665;
      --color-teal:   #8ec07c;
      --color-blue:   #5b84de;
      --color-violet: #d3869b;
      --color-purple: #d3869b;
      --color-pink:   #ea6962;

      --color-red-light:    #f08680;
      --color-orange-light: #fe9540;
      --color-yellow-light: #e8c074;
      --color-green-light:  #b9c578;
      --color-blue-light:   #7596e8;
      --color-violet-light: #dba0b0;

      --color-red-dark-1:    #c75d57;
      --color-orange-dark-1: #d96b15;
      --color-yellow-dark-1: #b8893f;
      --color-green-dark-1:  #8e9a55;
      --color-blue-dark-1:   #4d70bb;

      --color-success: #a9b665;
      --color-info:    #5b84de;
      --color-warning: #d8a657;
      --color-error:   #ea6962;
      --color-danger:  #ea6962;

      --color-code-bg:                 #1d2021;
      --color-markup-code-block:       #1d2021;
      --color-markup-code-inline:      #232425;
      --color-markup-table-row:        #ffffff06;
      --color-diff-removed-row-bg:     #4a2a28;
      --color-diff-removed-word-bg:    #6e3a36;
      --color-diff-added-row-bg:       #3a4128;
      --color-diff-added-word-bg:      #535e36;
      --color-diff-moved-row-bg:       #2c3e5e;
      --color-diff-added-row-border:   #a9b665;
      --color-diff-removed-row-border: #ea6962;
      --color-diff-moved-row-border:   #5b84de;
    }
    #navbar-logo { display: none !important; }
  '';

  forgejoCozyboxLightCss = pkgs.writeText "theme-cozybox-light.css" ''
    @import url("/assets/css/theme-forgejo-light.css");

    :root {
      --is-dark-theme: false;
      color-scheme: light;

      /* zinc ladder remapped to cozybox light bg->fg shades */
      --zinc-50:  #f9f5d7;
      --zinc-100: #fbf1c7;
      --zinc-150: #f2e5bc;
      --zinc-200: #ebdbb2;
      --zinc-250: #e1d3a6;
      --zinc-300: #d5c4a1;
      --zinc-350: #c8b599;
      --zinc-400: #bdae93;
      --zinc-450: #b0a08b;
      --zinc-500: #a89984;
      --zinc-550: #9e8e7c;
      --zinc-600: #928374;
      --zinc-650: #7c6f64;
      --zinc-700: #665c54;
      --zinc-750: #504945;
      --zinc-800: #3c3836;
      --zinc-850: #282828;
      --zinc-900: #1d2021;

      /* surface / structure */
      --color-body:               #fbf1c7;
      --color-box-body:           #f9f5d7;
      --color-box-body-highlight: #f2e5bc;
      --color-box-header:         #f2e5bc;
      --color-header-wrapper:     #f9f5d7;
      --color-footer:             #f9f5d7;
      --color-nav-bg:             #f2e5bc;
      --color-nav-hover-bg:       #ebdbb2;
      --color-secondary-nav-bg:   #fbf1c7;
      --color-card:               #f2e5bc;
      --color-menu:               #f2e5bc;
      --color-button:             #ebdbb2;
      --color-hover:              #ebdbb2;
      --color-active:             #d5c4a1;
      --color-timeline:           #d5c4a1;

      /* text */
      --color-text:             #282828;
      --color-text-dark:        #1d2021;
      --color-text-light:       #3c3836;
      --color-text-light-1:     #504945;
      --color-text-light-2:     #665c54;
      --color-text-light-3:     #7c6f64;
      --color-placeholder-text: #928374;

      /* secondary */
      --color-secondary:           #d5c4a1;
      --color-secondary-bg:        #ebdbb2;
      --color-secondary-dark-1:    #c8b599;
      --color-secondary-dark-2:    #bdae93;
      --color-secondary-light-1:   #e1d3a6;
      --color-secondary-light-2:   #ebdbb2;
      --color-secondary-light-3:   #f2e5bc;
      --color-secondary-light-4:   #f9f5d7;
      --color-secondary-alpha-60:  #d5c4a199;

      /* inputs */
      --color-input-background:   #f9f5d7;
      --color-input-text:         #282828;
      --color-input-border:       #d5c4a1;
      --color-input-border-hover: #bdae93;

      /* links */
      --color-link:       #458588;
      --color-link-hover: #3c7376;

      /* primary -> gruvbox neutral_blue (#458588) */
      --color-primary:          #458588;
      --color-primary-contrast: #ffffff;
      --color-primary-dark-1:   #569ba0;
      --color-primary-dark-2:   #6cb1b6;
      --color-primary-dark-3:   #82c6cb;
      --color-primary-dark-4:   #99dadf;
      --color-primary-dark-5:   #b0eef2;
      --color-primary-dark-6:   #c5f4f7;
      --color-primary-dark-7:   #dcfafc;
      --color-primary-light-1:  #3c7376;
      --color-primary-light-2:  #335d60;
      --color-primary-light-3:  #2a484a;
      --color-primary-light-4:  #213234;
      --color-primary-light-5:  #181d1e;
      --color-primary-light-6:  #0e0f0f;
      --color-primary-light-7:  #050505;
      --color-primary-alpha-10: #4585881a;
      --color-primary-alpha-20: #45858833;
      --color-primary-alpha-30: #4585884d;
      --color-primary-alpha-40: #45858866;
      --color-primary-alpha-50: #45858880;
      --color-primary-alpha-60: #45858899;
      --color-primary-alpha-70: #458588b3;
      --color-primary-alpha-80: #458588cc;
      --color-primary-alpha-90: #458588e6;
      --color-primary-hover:    var(--color-primary-light-1);
      --color-primary-active:   var(--color-primary-light-2);
      --color-accent:           #458588;

      /* cozybox light accents (gruvbox neutrals) */
      --color-red:    #cc241d;
      --color-orange: #d65d0e;
      --color-yellow: #d79921;
      --color-olive:  #98971a;
      --color-green:  #98971a;
      --color-teal:   #689d6a;
      --color-blue:   #458588;
      --color-violet: #b16286;
      --color-purple: #b16286;
      --color-pink:   #cc241d;

      --color-success: #98971a;
      --color-info:    #458588;
      --color-warning: #d79921;
      --color-error:   #cc241d;
      --color-danger:  #cc241d;

      --color-code-bg:                 #f2e5bc;
      --color-markup-code-block:       #f2e5bc;
      --color-markup-code-inline:      #ebdbb2;
      --color-diff-removed-row-bg:     #f2cfc6;
      --color-diff-removed-word-bg:    #e2a1b2;
      --color-diff-added-row-bg:       #d5e3b8;
      --color-diff-added-word-bg:      #a5c5ab;
      --color-diff-moved-row-bg:       #c0d0e8;
      --color-diff-added-row-border:   #98971a;
      --color-diff-removed-row-border: #cc241d;
      --color-diff-moved-row-border:   #458588;
    }
    #navbar-logo { display: none !important; }
  '';

  forgejoCozyboxAutoCss = pkgs.writeText "theme-cozybox-auto.css" ''
    @import url("/assets/css/theme-cozybox-light.css");
    @import url("/assets/css/theme-cozybox-dark.css") (prefers-color-scheme: dark);
  '';
in
{
  services.caddy.virtualHosts."http://${forgejoDomain}" = loopbackVhost backendPort;

  sops.secrets."forgejo-smtp-password" = mkSparkSecret "forgejo-smtp-password" {
    owner = "git";
    group = "git";
    mode = "0400";
    restartUnits = [ "forgejo.service" ];
  };
  sops.secrets."forgejo-mirror.env" = mkSparkSecret "forgejo-mirror.env" {
    owner = "git";
    group = "git";
    mode = "0400";
    restartUnits = [
      "forgejo.service"
      "forgejo-mirror-sync.service"
    ];
  };
  sops.secrets."forgejo-runner-token" = mkSparkSecret "forgejo-runner-token" {
    owner = "gitea-runner";
    group = "gitea-runner";
    mode = "0400";
    restartUnits = [ "gitea-runner-netty.service" ];
  };

  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };
  users.groups.git = { };

  systemd.services.forgejo.preStart = lib.mkAfter ''
    . ${mirrorEnvFile}
    printf 'https://oauth2:%s@github.com\n' "$GITHUB_TOKEN" > ${gitCredentialFile}
    chmod 600 ${gitCredentialFile}
  '';

  services.forgejo = {
    enable = true;
    user = "git";
    group = "git";
    secrets.mailer.PASSWD = smtpPasswordFile;
    settings = {
      "git.config" = {
        "credential.helper" = "store --file ${gitCredentialFile}";
      };
      repository = {
        DEFAULT_PRIVATE = "private";
        DEFAULT_PUSH_CREATE_PRIVATE = true;
      };
      server = {
        DOMAIN = forgejoDomain;
        ROOT_URL = "https://${forgejoDomain}/";
        HTTP_PORT = backendPort;
        SSH_DOMAIN = forgejoDomain;
      };
      service = {
        DISABLE_REGISTRATION = false;
        REQUIRE_SIGNIN_VIEW = false;
        DEFAULT_USER_IS_RESTRICTED = false;
        REGISTER_EMAIL_CONFIRM = true;
        SEND_NOTIFICATION_EMAIL_ON_NEW_USER = true;
      };
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtps";
        SMTP_ADDR = "smtp.resend.com";
        SMTP_PORT = 465;
        USER = "resend";
        FROM = "Forgejo <noreply@${rootDomain}>";
      };
      session.COOKIE_SECURE = true;
      mirror = {
        DEFAULT_INTERVAL = "1h";
        MIN_INTERVAL = "10m";
      };
      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "https://github.com";
      };
      ui = {
        DEFAULT_THEME = "cozybox-auto";
        THEMES = "cozybox-auto,cozybox-light,cozybox-dark,forgejo-auto,forgejo-dark,forgejo-light";
      };
    };
  };

  systemd.services.forgejo-mirror-sync = {
    description = "Sync GitHub mirrors to Forgejo";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "git";
      Group = "git";
      EnvironmentFile = mirrorEnvFile;
    };
    path = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.gnused
      pkgs.git
      pkgs.sqlite
    ];
    script = ''
      set -euo pipefail

      api_call() {
        local response http_code body
        response=$(curl -sS -w "\n%{http_code}" "$@")
        http_code=$(printf '%s\n' "$response" | tail -n1)
        body=$(printf '%s\n' "$response" | sed '$d')
        if [ "$http_code" -ge 400 ]; then
          printf '[forgejo-mirror-sync] HTTP %s\n' "$http_code" >&2
          printf '%s\n' "$body" >&2
          return 1
        fi
        printf '%s' "$body"
      }

      fix_mirror_creds() {
        local forgejo_owner="$1" repo_name="$2" wait_for_create="''${3:-false}"
        local repo_dir="/var/lib/forgejo/repositories/$forgejo_owner/$repo_name.git"
        if [ "$wait_for_create" = "true" ]; then
          local tries=0
          while [ ! -d "$repo_dir" ] && [ "$tries" -lt 10 ]; do
            sleep 2
            tries=$((tries + 1))
          done
        fi
        if [ -d "$repo_dir" ]; then
          local current_url
          current_url=$(git --git-dir="$repo_dir" config --get remote.origin.url 2>/dev/null || true)
          if [ -n "$current_url" ] && ! echo "$current_url" | grep -q "$GITHUB_TOKEN"; then
            local new_url
            new_url=$(printf '%s' "$current_url" | sed "s|https://oauth2@github.com/|https://oauth2:$GITHUB_TOKEN@github.com/|; s|https://github.com/|https://oauth2:$GITHUB_TOKEN@github.com/|")
            git --git-dir="$repo_dir" remote set-url origin "$new_url" 2>/dev/null || true
          fi
        fi
      }

      clean_db_url() {
        local forgejo_owner="$1" repo_name="$2" clone_url="$3"
        local clean_url
        clean_url=$(printf '%s' "$clone_url" | sed 's|https://oauth2:[^@]*@github.com/|https://github.com/|')
        local repo_id
        repo_id=$(sqlite3 /var/lib/forgejo/data/forgejo.db \
          ".timeout 5000" \
          "SELECT r.id FROM repository r JOIN \"user\" u ON r.owner_id=u.id WHERE u.lower_name=LOWER('$forgejo_owner') AND r.lower_name=LOWER('$repo_name');")
        if [ -n "$repo_id" ]; then
          sqlite3 /var/lib/forgejo/data/forgejo.db \
            ".timeout 5000" \
            "UPDATE mirror SET remote_address='$clean_url' WHERE repo_id=$repo_id AND remote_address LIKE '%ghp_%';"
        fi
      }

      ensure_org() {
        local org_name="$1"
        local status
        status=$(curl -sS -o /dev/null -w '%{http_code}' \
          -H "Authorization: token $FORGEJO_TOKEN" \
          "${forgejoApiUrl}/api/v1/orgs/$org_name" || true)
        if [ "$status" = "404" ]; then
          api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            "${forgejoApiUrl}/api/v1/orgs" \
            -d "$(jq -n --arg name "$org_name" '{
              username: $name,
              visibility: "private"
            }')" > /dev/null
          echo "Created org: $org_name"
        fi
      }

      gh_user=$(api_call -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/user" | jq -r '.login')

      repos_file=$(mktemp)
      trap 'rm -f "$repos_file"' EXIT

      page=1
      while true; do
        batch=$(api_call -H "Authorization: token $GITHUB_TOKEN" \
          "https://api.github.com/user/repos?per_page=100&page=$page&visibility=all&affiliation=owner,organization_member")
        count=$(printf '%s' "$batch" | jq length)
        [ "$count" -eq 0 ] && break
        printf '%s' "$batch" | jq -r '.[] | [.full_name, .clone_url] | @tsv' >> "$repos_file"
        page=$((page + 1))
      done

      sort -u "$repos_file" -o "$repos_file"

      while IFS=$'\t' read -r full_name clone_url; do
        repo_owner="''${full_name%%/*}"
        repo_name="''${full_name#*/}"

        if [ "$repo_owner" = "$gh_user" ]; then
          forgejo_owner="$FORGEJO_OWNER"
        else
          forgejo_owner="$repo_owner"
          ensure_org "$repo_owner"
        fi

        status=$(curl -sS -o /dev/null -w '%{http_code}' \
          -H "Authorization: token $FORGEJO_TOKEN" \
          "${forgejoApiUrl}/api/v1/repos/$forgejo_owner/$repo_name" || true)

        if [ "$status" = "404" ]; then
          api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            "${forgejoApiUrl}/api/v1/repos/migrate" \
            -d "$(jq -n \
              --arg addr "$clone_url" \
              --arg name "$repo_name" \
              --arg owner "$forgejo_owner" \
              --arg token "$GITHUB_TOKEN" \
              '{
                clone_addr: $addr,
                repo_name: $name,
                repo_owner: $owner,
                private: true,
                mirror: true,
                auth_token: $token,
                service: "github"
              }')" \
            > /dev/null
          fix_mirror_creds "$forgejo_owner" "$repo_name" true
          clean_db_url "$forgejo_owner" "$repo_name" "$clone_url"
          echo "Created mirror: $full_name -> $forgejo_owner/$repo_name"
        else
          fix_mirror_creds "$forgejo_owner" "$repo_name"
          clean_db_url "$forgejo_owner" "$repo_name" "$clone_url"
          if ! api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            "${forgejoApiUrl}/api/v1/repos/$forgejo_owner/$repo_name/mirror-sync" \
            > /dev/null; then
            echo "Failed mirror sync: $full_name -> $forgejo_owner/$repo_name" >&2
            continue
          fi
          echo "Synced mirror: $full_name -> $forgejo_owner/$repo_name"
        fi
      done < "$repos_file"
    '';
  };

  systemd.timers.forgejo-mirror-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };

  systemd.services.forgejo-heatmap-reconcile = {
    description = "Reconcile Forgejo heatmap with mirrored commit history";
    after = [
      "forgejo.service"
      "forgejo-mirror-sync.service"
    ];
    requires = [ "forgejo.service" ];
    wantedBy = [ "forgejo-mirror-sync.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = mirrorEnvFile;
      User = "git";
      Group = "git";
    };
    path = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.sqlite
      pkgs.gnused
    ];
    script = ''
      set -euo pipefail

      DB="/var/lib/forgejo/data/forgejo.db"
      API="${forgejoApiUrl}/api/v1"
      OP_TYPE=5

      api() {
        curl -sS -H "Authorization: token $FORGEJO_TOKEN" "$@"
      }

      me=$(api "$API/user")
      user_id=$(printf '%s' "$me" | jq -r '.id')
      login=$(printf '%s' "$me" | jq -r '.login')

      emails=$(api "$API/user/emails" | jq -r '.[].email')
      primary=$(printf '%s' "$me" | jq -r '.email')
      all_emails=$(printf '%s\n%s' "$primary" "$emails" | sort -u | grep -v '^$')

      echo "Reconciling heatmap for $login (id=$user_id)"

      repo_list=$(mktemp)
      trap 'rm -f "$repo_list"' EXIT

      fetch_repos() {
        local url="$1" p=1
        while true; do
          local batch
          batch=$(api "$url?page=$p&limit=50&type=mirrors") || break
          local n
          n=$(printf '%s' "$batch" | jq length)
          [ "$n" -eq 0 ] && break
          printf '%s' "$batch" | jq -c '.[]' >> "$repo_list"
          p=$((p + 1))
        done
      }

      fetch_repos "$API/user/repos"

      orgs=$(api "$API/user/orgs" | jq -r '.[].username')
      for org in $orgs; do
        fetch_repos "$API/orgs/$org/repos"
      done

      inserted=0

      while read -r repo; do
        repo_id=$(printf '%s' "$repo" | jq -r '.id')
        owner=$(printf '%s' "$repo" | jq -r '.owner.login')
        name=$(printf '%s' "$repo" | jq -r '.name')
        branch=$(printf '%s' "$repo" | jq -r '.default_branch')

        latest=$(sqlite3 "$DB" \
          ".timeout 5000" \
          "SELECT COALESCE(MAX(created_unix),0) FROM action WHERE repo_id=$repo_id AND act_user_id=$user_id AND op_type=$OP_TYPE;")

        since_param=""
        if [ "$latest" -gt 0 ]; then
          since_iso=$(date -u -d "@$((latest + 1))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
          [ -n "$since_iso" ] && since_param="&since=$since_iso"
        fi

        cpage=1
        repo_added=0
        while true; do
          commits=$(api "$API/repos/$owner/$name/commits?sha=$branch&page=$cpage&limit=50$since_param" 2>/dev/null) || break
          ccount=$(printf '%s' "$commits" | jq 'if type == "array" then length else 0 end')
          [ "$ccount" -eq 0 ] && break

          commit_file=$(mktemp)
          printf '%s' "$commits" | jq -c '.[]' > "$commit_file"

          while read -r commit; do
            author_email=$(printf '%s' "$commit" | jq -r '.commit.author.email // empty')
            [ -z "$author_email" ] && continue

            matched=0
            while IFS= read -r e; do
              [ "$author_email" = "$e" ] && matched=1 && break
            done <<< "$all_emails"
            [ "$matched" -eq 0 ] && continue

            iso_date=$(printf '%s' "$commit" | jq -r '.commit.author.date')
            created_unix=$(date -u -d "$iso_date" +%s 2>/dev/null || echo "")
            [ -z "$created_unix" ] && continue

            sha=$(printf '%s' "$commit" | jq -r '.sha')
            content="$branch\n$sha"

            exists=$(sqlite3 "$DB" \
              ".timeout 5000" \
              "SELECT COUNT(*) FROM action WHERE user_id=$user_id AND repo_id=$repo_id AND op_type=$OP_TYPE AND created_unix=$created_unix;")
            [ "$exists" -gt 0 ] && continue

            sqlite3 "$DB" \
              ".timeout 5000" \
              "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $OP_TYPE, $user_id, $repo_id, 'refs/heads/$branch', 1, '$content', $created_unix);"

            repo_added=$((repo_added + 1))
            inserted=$((inserted + 1))
          done < "$commit_file"
          rm -f "$commit_file"

          cpage=$((cpage + 1))
        done

        [ "$repo_added" -gt 0 ] && echo "  $owner/$name: +$repo_added commits"
      done < "$repo_list"

      echo "Reconciliation complete: $inserted new action records."
    '';
  };

  systemd.services.gitea-runner-netty.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "gitea-runner";
    Group = lib.mkForce "gitea-runner";
    NoNewPrivileges = lib.mkForce false;
    RestrictSUIDSGID = lib.mkForce false;
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

    "d /var/lib/forgejo/custom 0750 git git -"
    "d /var/lib/forgejo/custom/public 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets/css 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets/img 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-cozybox-auto.css - - - - ${forgejoCozyboxAutoCss}"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-cozybox-light.css - - - - ${forgejoCozyboxLightCss}"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-cozybox-dark.css - - - - ${forgejoCozyboxDarkCss}"
    "L+ /var/lib/forgejo/custom/public/assets/img/favicon.svg - - - - ${forgejoBrandingAssets}/favicon.svg"
    "L+ /var/lib/forgejo/custom/public/assets/img/favicon.png - - - - ${forgejoBrandingAssets}/favicon.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/logo.svg - - - - ${forgejoBrandingAssets}/logo.svg"
    "L+ /var/lib/forgejo/custom/public/assets/img/logo.png - - - - ${forgejoBrandingAssets}/logo.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/apple-touch-icon.png - - - - ${forgejoBrandingAssets}/apple-touch-icon.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/avatar_default.png - - - - ${forgejoBrandingAssets}/avatar_default.png"
  ];

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;

    instances.netty = {
      enable = true;
      name = "netty";
      url = "https://${forgejoDomain}";
      tokenFile = runnerTokenFile;

      labels = [
        "native:host"
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
