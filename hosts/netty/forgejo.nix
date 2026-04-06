{
  pkgs,
  lib,
  username,
  ...
}:
let
  forgejoDomain = "git.harivan.sh";
  forgejoApiUrl = "http://127.0.0.1:19300";
  gitCredentialFile = "/var/lib/forgejo/.git-credentials";
  mirrorEnvFile = "/etc/forgejo-mirror.env";
in
{
  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };
  users.groups.git = { };

  # Generate git credential store for GitHub mirror fetches.
  # Appended after the module's own preStart (which handles app.ini and migrations).
  # preStart runs as the forgejo user (git), and the env file is world-readable.
  systemd.services.forgejo.preStart = lib.mkAfter ''
    . ${mirrorEnvFile}
    printf 'https://oauth2:%s@github.com\n' "$GITHUB_TOKEN" > ${gitCredentialFile}
    chmod 600 ${gitCredentialFile}
  '';

  services.forgejo = {
    enable = true;
    user = "git";
    group = "git";
    settings = {
      "git.config" = {
        "credential.helper" = "store --file ${gitCredentialFile}";
      };
      repository = {
        FORCE_PRIVATE = true;
        DEFAULT_PRIVATE = "private";
        DEFAULT_PUSH_CREATE_PRIVATE = true;
      };
      server = {
        DOMAIN = forgejoDomain;
        ROOT_URL = "https://${forgejoDomain}/";
        HTTP_PORT = 19300;
        SSH_DOMAIN = forgejoDomain;
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
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
      EnvironmentFile = "/etc/forgejo-mirror.env";
    };
    path = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.gnused
      pkgs.git
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
        local forgejo_owner="$1" repo_name="$2"
        local repo_dir="/var/lib/forgejo/repositories/$forgejo_owner/$repo_name.git"
        # Wait briefly for async migration to create the bare repo
        local tries=0
        while [ ! -d "$repo_dir" ] && [ "$tries" -lt 10 ]; do
          sleep 2
          tries=$((tries + 1))
        done
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
          fix_mirror_creds "$forgejo_owner" "$repo_name"
          echo "Created mirror: $full_name -> $forgejo_owner/$repo_name"
        else
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
}
