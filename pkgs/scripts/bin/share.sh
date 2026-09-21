die() {
  echo "share: $*" >&2
  exit 1
}
usage() {
  cat <<'EOF'
Usage: share FILE_OR_DIRECTORY [--edit] [--expires 30m|2h|7d|2w] [--password]

Publish a copy and print its public URL. Originals stay unchanged.
Directory shares exclude dotfiles. Symlinks and special files are rejected.
--edit permits Markdown/text editing, plus uploads for folder shares.
Links do not expire unless --expires is given. Manage/revoke links in the web UI.
Authentication uses Spark's credential locally, or your existing SSH access to Spark.
EOF
}

[[ $# -gt 0 ]] || {
  usage
  exit 0
}

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
umask 077
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
server=${SHARE_SERVER:-https://files.harivan.sh}
credential=${SHARE_PASSWORD_FILE:-/run/secrets/copyparty-password}
if [[ -z ${SHARE_SERVER:-} && -r /run/secrets/copyparty-password ]]; then
  server=http://127.0.0.1:39473
elif [[ $server != https://files.harivan.sh ]]; then
  [[ -n ${SHARE_PASSWORD_FILE:-} ]] || die 'a custom server requires SHARE_PASSWORD_FILE'
  [[ $server =~ ^https://[a-zA-Z0-9.:-]+$ || $server =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || die 'HTTPS required'
fi
if [[ -r $credential ]]; then
  account_password=$(cat -- "$credential")
else
  [[ -z ${SHARE_PASSWORD_FILE:-} ]] || die 'credential file is not readable'
  account_password=$(ssh -T -o BatchMode=yes -o ConnectTimeout=10 spark cat /run/secrets/copyparty-password) || die 'cannot authenticate; check SSH access to Spark'
fi
[[ -n $account_password && $account_password != *$'\r'* && $account_password != *$'\n'* ]] || die 'invalid account credential'
printf 'PW: %s\n' "$account_password" >"$work/headers"
http=(curl -q --silent --show-error --connect-timeout 10 --max-time 60 --header "@$work/headers")
request() { "${http[@]}" --fail "$@"; }
request "$server/?ls" | jq -e '.perms | index("write") != null' >/dev/null || die 'server rejected the account credential'
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
  status=$("${http[@]}" --request MKCOL --output /dev/null --write-out '%{http_code}' "$server$(encode_path "$1")")
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
[[ ! -t 2 ]] || printf 'Sharing %s…\n' "$name" >&2
export U2C_PW=$account_password
exclude=$(jq -rn --arg path "$source_path" '$path | gsub("(?<c>[.\\\\+*?\\[\\](){}^$|])"; "\\" + .c)')
if ! python3 @UPLOADER@ -ns --sz 16 --szm 32 --t-hs 30 -x "^$exclude/(?:.*/)?\.[^/]+(?:/|$)" "$server$base/" "$source_path" >"$work/upload.log" 2>&1; then
  cat "$work/upload.log" >&2
  die 'upload failed; partial files remain private in the web file manager'
fi
unset U2C_PW account_password
path="$base/$name"
[[ ! -d $source_path ]] || path+=/
jq -n --arg key "$key" --arg path "$path" --argjson edit "$edit" --argjson expiry "$expires" --rawfile password "$work/share-password" \
  '{k: $key, vp: [$path], perms: (["read"] + (if $edit then ["write"] else [] end) + (if ($path | split("/") | any(startswith("."))) then ["dot"] else [] end)), pw: $password, exp: $expiry}' >"$work/request.json"
response=$(request --header 'Content-Type: application/json' --data-binary "@$work/request.json" "$server/?share") || die "share creation not confirmed; inspect the web share list for $key before retrying"
[[ $response == 'created share: '* ]] || die 'unexpected sharing response; inspect the web share list'
printf '%s\n' "${response#created share: }"
