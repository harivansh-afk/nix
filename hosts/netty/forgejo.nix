{
  pkgs,
  username,
  ...
}:
let
  forgejoDomain = "git.harivan.sh";
  forgejoApiUrl = "http://127.0.0.1:19300";
in
{
  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };
  users.groups.git = { };

  services.forgejo = {
    enable = true;
    user = "git";
    group = "git";
    settings = {
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
          forgejo_repo_name="$repo_name"
        else
          forgejo_repo_name="$repo_owner--$repo_name"
        fi

        status=$(curl -sS -o /dev/null -w '%{http_code}' \
          -H "Authorization: token $FORGEJO_TOKEN" \
          "${forgejoApiUrl}/api/v1/repos/$FORGEJO_OWNER/$forgejo_repo_name" || true)

        if [ "$status" = "404" ]; then
          api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            "${forgejoApiUrl}/api/v1/repos/migrate" \
            -d "$(jq -n \
              --arg addr "$clone_url" \
              --arg name "$forgejo_repo_name" \
              --arg owner "$FORGEJO_OWNER" \
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
          echo "Created mirror: $full_name -> $FORGEJO_OWNER/$forgejo_repo_name"
        else
          if ! api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            "${forgejoApiUrl}/api/v1/repos/$FORGEJO_OWNER/$forgejo_repo_name/mirror-sync" \
            > /dev/null; then
            echo "Failed mirror sync: $full_name -> $FORGEJO_OWNER/$forgejo_repo_name" >&2
            continue
          fi
          echo "Synced mirror: $full_name -> $FORGEJO_OWNER/$forgejo_repo_name"
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
