{
  config,
  pkgs,
  lib,
  loopbackVhost,
  ...
}:
let
  rootDomain = "harivan.sh";
  forgejoDomain = "git.${rootDomain}";
  backendPort = 19300;
  forgejoApiUrl = "http://127.0.0.1:${toString backendPort}";
  gitCredentialFile = "/var/lib/forgejo/.git-credentials";
  # sops deposits the plaintexts under /run/secrets/<name> at activation.
  smtpPasswordFile = config.sops.secrets."forgejo-smtp-password".path;
  mirrorEnvFile = config.sops.secrets."forgejo-mirror.env".path;
  runnerTokenFile = config.sops.secrets."forgejo-runner-token".path;
  # Cache root for tooling used inside CI jobs (npm, pip, cargo, ...).
  runnerCacheRoot = "/var/cache/forgejo-runner";
in
{
  services.caddy.virtualHosts."http://${forgejoDomain}" = loopbackVhost backendPort;

  sops.secrets."forgejo-smtp-password" = {
    sopsFile = ../../secrets/spark/forgejo-smtp-password;
    format = "binary";
    owner = "git";
    group = "git";
    mode = "0400";
    restartUnits = [ "forgejo.service" ];
  };
  sops.secrets."forgejo-mirror.env" = {
    sopsFile = ../../secrets/spark/forgejo-mirror.env;
    format = "binary";
    owner = "git";
    group = "git";
    mode = "0400";
    restartUnits = [
      "forgejo.service"
      "forgejo-mirror-sync.service"
      "forgejo-heatmap-reconcile.service"
    ];
  };
  sops.secrets."forgejo-runner-token" = {
    sopsFile = ../../secrets/spark/forgejo-runner-token;
    format = "binary";
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

  # Generate the git credential store used by mirror-sync fetches from
  # GitHub. Runs as the `git` user after the module's own preStart
  # (which handles app.ini + schema migrations). Sources the mirror env
  # from /run/secrets/forgejo-mirror.env where sops-nix deposits it.
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
    };
  };

  # --- Forgejo mirror sync (hourly) ---
  systemd.services.forgejo-mirror-sync = {
    description = "Sync GitHub mirrors to Forgejo";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
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

      # Ensure the bare repo git config has the token for fetching,
      # but keep the DB remote_address clean (no token) so the UI
      # never exposes it.
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

  # --- Forgejo heatmap reconciliation ---
  # Runs after every mirror sync. Scans each repo for commits authored by the
  # Forgejo user and inserts ActionCommitRepo (op_type=5) records into the
  # action table so they appear in the contribution heatmap.
  #
  # Uses the action table itself as the cursor: for each repo it queries the
  # most recent recorded timestamp, then fetches only newer commits via the
  # Forgejo API "since" parameter. First run = full backfill, subsequent
  # runs = incremental. Idempotent and safe to re-run.
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
      OP_TYPE=5  # ActionCommitRepo

      api() {
        curl -sS -H "Authorization: token $FORGEJO_TOKEN" "$@"
      }

      # --- resolve identity ---
      me=$(api "$API/user")
      user_id=$(printf '%s' "$me" | jq -r '.id')
      login=$(printf '%s' "$me" | jq -r '.login')

      emails=$(api "$API/user/emails" | jq -r '.[].email')
      primary=$(printf '%s' "$me" | jq -r '.email')
      all_emails=$(printf '%s\n%s' "$primary" "$emails" | sort -u | grep -v '^$')

      echo "Reconciling heatmap for $login (id=$user_id)"

      # --- collect every repo the user can see (personal + orgs) ---
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

      # personal repos
      fetch_repos "$API/user/repos"

      # org repos
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

        # find the latest commit we already recorded for this repo
        latest=$(sqlite3 "$DB" \
          ".timeout 5000" \
          "SELECT COALESCE(MAX(created_unix),0) FROM action WHERE repo_id=$repo_id AND act_user_id=$user_id AND op_type=$OP_TYPE;")

        # convert to ISO 8601 "since" param (skip if no prior records -> fetch all)
        since_param=""
        if [ "$latest" -gt 0 ]; then
          # add 1 second to avoid re-processing the boundary commit
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

            # match against our emails
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

            # deduplicate on repo + user + timestamp
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

  # --- Forgejo Actions runner ---
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
