die() {
  echo "share: $*" >&2
  exit 1
}
usage() {
  cat <<'EOF'
Usage: share FILE_OR_DIRECTORY [--edit] [--expires 30m|2h|7d|2w] [--password]
       share login

Publish a copy and print its public URL. Originals stay unchanged.
Directory shares exclude dotfiles. Symlinks and special files are rejected.
--edit permits Markdown/text editing, plus uploads for folder shares.
Links do not expire unless --expires is given. Manage/revoke links in the web UI.
On Spark authentication is automatic; elsewhere run share login once.
EOF
}

umask 077
default_server=https://files.harivan.sh
server=${SHARE_SERVER:-$default_server}
credential=${SHARE_PASSWORD_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/share/password}
if [[ $server != "$default_server" ]]; then
  [[ -n ${SHARE_PASSWORD_FILE:-} ]] || die 'a custom server requires SHARE_PASSWORD_FILE'
  [[ $server =~ ^https://[a-zA-Z0-9.:-]+$ || $server =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || die 'invalid server origin; HTTPS required'
elif [[ -z ${SHARE_PASSWORD_FILE:-} && -r /run/secrets/copyparty-password ]]; then
  credential=/run/secrets/copyparty-password
fi

[[ $# -gt 0 ]] || {
  usage
  exit 0
}
[[ $1 != --help && $1 != -h ]] || {
  usage
  exit 0
}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
if [[ $1 == login ]]; then
  [[ $# == 1 ]] || die 'usage: share login'
  IFS= read -rs -p 'Copyparty account password: ' account_password
  printf '\n' >&2
else
  [[ -r $credential ]] || die 'run share login first, or set SHARE_PASSWORD_FILE'
  account_password=$(cat -- "$credential")
fi
[[ -n $account_password && $account_password != *$'\r'* && $account_password != *$'\n'* ]] || die 'invalid account password'
printf 'PW: %s\n' "$account_password" >"$work/headers"
request() { curl -q --fail --silent --show-error --connect-timeout 10 --max-time 60 --header "@$work/headers" "$@"; }
request "$server/?ls" | jq -e '.perms | index("write") != null' >/dev/null || die 'authentication failed'
if [[ $1 == login ]]; then
  [[ $credential != /run/secrets/* ]] || {
    echo 'Spark already supplies your credential.' >&2
    exit 0
  }
  mkdir -p -- "$(dirname -- "$credential")"
  [[ ! -L $credential ]] || die 'credential path must not be a symlink'
  printf '%s' "$account_password" >"$work/password"
  install -m 600 "$work/password" "$credential"
  echo 'Credential saved.' >&2
  exit 0
fi

source_path='' edit=false protected=false expires=0
while [[ $# -gt 0 ]]; do
  case $1 in
  --edit) edit=true ;;
  --password) protected=true ;;
  --expires)
    shift
    [[ ${1:-} =~ ^([1-9][0-9]{0,5})(m|h|d|w)$ ]] || die 'use --expires 30m, 2h, 7d, or 2w'
    expires=${BASH_REMATCH[1]}
    case ${BASH_REMATCH[2]} in
    h) expires=$((expires * 60)) ;;
    d) expires=$((expires * 1440)) ;;
    w) expires=$((expires * 10080)) ;;
    esac
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  --)
    shift
    [[ $# == 1 && -z $source_path ]] || die 'expected one path'
    source_path=$1
    break
    ;;
  -*) die "unknown option: $1" ;;
  *)
    [[ -z $source_path ]] || die 'publish one path at a time'
    source_path=$1
    ;;
  esac
  shift
done
[[ -n $source_path && ! -L $source_path ]] || die 'select a regular file or directory, not a symlink'
source_path=$(realpath -e -- "$source_path")
[[ -f $source_path || -d $source_path ]] || die 'source must be a regular file or directory'
name=$(basename -- "$source_path")
[[ $source_path != / ]] || die 'cannot publish the filesystem root'
[[ $source_path != *$'\n'* && $source_path != *$'\r'* ]] || die 'path contains a newline'
tree() { find "$source_path" -mindepth 1 -name '.*' -prune -o "$@"; }
[[ -z $(tree ! -type f ! -type d -print -quit) ]] || die 'directory contains a symlink or special file'
printf '' >"$work/share-password"
if $protected; then
  IFS= read -rs -p 'Password for this link: ' share_password
  printf '\n' >&2
  [[ -n $share_password ]] || die 'share password must not be empty'
  printf '%s' "$share_password" >"$work/share-password"
fi

key=$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')
base="/published/$key"
encode_path() { jq -rn --arg path "$1" '$path | split("/") | map(@uri) | join("/")'; }
mkdir_remote() {
  local status
  status=$(curl -q --silent --show-error --connect-timeout 10 --max-time 60 --header "@$work/headers" --request MKCOL --output /dev/null --write-out '%{http_code}' "$server$(encode_path "$1")")
  [[ $status == 201 || $status == 405 ]] || die "could not create upload directory (HTTP $status)"
}
mkdir_remote /published
mkdir_remote "$base"
if [[ -d $source_path ]]; then
  mkdir_remote "$base/$name"
  while IFS= read -r -d '' directory; do
    mkdir_remote "$base/${directory#"$(dirname -- "$source_path")"/}"
  done < <(tree -type d -print0)
fi
echo 'Uploading a copy…' >&2
export U2C_PW=$account_password
exclude=$(jq -rn --arg path "$source_path" '$path | gsub("(?<c>[.\\\\+*?\\[\\](){}^$|])"; "\\" + .c)')
python3 @UPLOADER@ -ns --sz 16 --szm 32 --t-hs 30 -x "^$exclude/(?:.*/)?\.[^/]+(?:/|$)" "$server$base/" "$source_path" >&2 || die 'upload failed; partial files remain private in the web file manager'
unset U2C_PW account_password
path="$base/$name"
[[ ! -d $source_path ]] || path+=/
jq -n --arg key "$key" --arg path "$path" --argjson edit "$edit" --argjson expiry "$expires" --rawfile password "$work/share-password" \
  '{k: $key, vp: [$path], perms: (["read"] + (if $edit then ["write"] else [] end) + (if ($path | split("/") | any(startswith("."))) then ["dot"] else [] end)), pw: $password, exp: $expiry}' >"$work/request.json"
response=$(request --header 'Content-Type: application/json' --data-binary "@$work/request.json" "$server/?share") || die "share creation not confirmed; inspect the web share list for $key before retrying"
[[ $response == 'created share: '* ]] || die 'unexpected sharing response; inspect the web share list'
printf '%s\n' "${response#created share: }"
