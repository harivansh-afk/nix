"""Mirror every GitHub org repo into Forgejo. Runs as the git user on a timer.

Only ever adds or protects; it never deletes or converts a repo.

1. Each GitHub account (GITHUB_TOKEN, plus GITHUB_TOKEN_<NAME> for separate
   logins) lists every org repo it can see. Each one missing from the forge
   becomes a private pull mirror under a forge org of the same name, cloned
   with that account's token, which forgejo stores encrypted per mirror.
2. Every pull mirror has pruning off, so branches deleted upstream stay.
3. Owned pull mirrors are GitHub-canonical and keep no push mirror.
4. Every other owned repo gets a push mirror to the same-named GitHub repo,
   which is created with the forge visibility if missing. An existing GitHub
   repo is only adopted when the forge already has every one of its branch
   heads, so the mirror's force push cannot drop work.
5. Forgejo Actions are on exactly for the manifest allowlist.

Environment: MIRROR_MANIFEST, FORGEJO_API, FORGEJO_TOKEN, GITHUB_TOKEN,
GITHUB_TOKEN_<NAME> (optional), DRY_RUN (optional, "1" logs only).
"""

import json
import os
import sys
import urllib.error
import urllib.request

MANIFEST = json.load(open(os.environ["MIRROR_MANIFEST"]))
FORGEJO_API = os.environ["FORGEJO_API"].rstrip("/")
FORGEJO_TOKEN = os.environ["FORGEJO_TOKEN"]
DRY = os.environ.get("DRY_RUN") == "1"

OWNER = MANIFEST["owned_owner"].lower()
IGNORED_ORGS = {o.lower() for o in MANIFEST["ignored_orgs"]}
ACTIONS = {r.lower() for r in MANIFEST["actions_enabled_repos"]}
TOKENS = {
    name.removeprefix("GITHUB_TOKEN").lstrip("_").lower() or "default": value
    for name, value in os.environ.items()
    if name.startswith("GITHUB_TOKEN") and value
}


class HTTPError(Exception):
    def __init__(self, status, body):
        super().__init__(f"HTTP {status}: {body[:300]}")
        self.status = status


def request(base, token, method, path, body=None, timeout=60):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Authorization", f"token {token}")
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    attempts = 3 if method == "GET" else 1
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
            break
        except urllib.error.HTTPError as e:
            raise HTTPError(e.code, e.read().decode(errors="replace")) from None
        except TimeoutError:
            if attempt == attempts - 1:
                raise
            print(f"GET {path} timed out; retrying", flush=True)
    return json.loads(raw) if raw else None


def forge(method, path, body=None, timeout=20):
    return request(FORGEJO_API, FORGEJO_TOKEN, method, path, body, timeout)


def pages(fetch, path, size, key=None):
    page = 1
    sep = "&" if "?" in path else "?"
    while True:
        batch = fetch("GET", f"{path}{sep}limit={size}&per_page={size}&page={page}")
        batch = batch[key] if key else batch
        yield from batch
        if len(batch) < size:
            return
        page += 1


def act(message, fn, *args, **kwargs):
    print(message, flush=True)
    if DRY:
        return None
    try:
        return fn(*args, **kwargs)
    except (HTTPError, TimeoutError) as e:
        print(f"  failed: {e}", flush=True)
        return None


def github_client(token):
    def github(method, path, body=None):
        return request("https://api.github.com", token, method, path, body)
    return github


def github_repos():
    repos = {}
    for account, token in sorted(TOKENS.items(), key=lambda t: t[0] != "default"):
        github = github_client(token)
        try:
            github("GET", "/user")
        except HTTPError as e:
            print(f"github account {account}: token rejected ({e}); skipping it")
            continue
        affiliation = "/user/repos?affiliation=owner,collaborator,organization_member"
        for repo in pages(github, affiliation, 100):
            repos.setdefault(repo["full_name"].lower(), (account, repo))
    return repos


def ensure_org(name, orgs):
    if name.lower() not in orgs:
        act(f"{name}: creating private org", forge, "POST", "/orgs",
            {"username": name, "visibility": "private"})
        orgs[name.lower()] = name
    return orgs[name.lower()]


def sync_pull_mirrors(gh_repos, repos, orgs):
    for path, (account, gh) in sorted(gh_repos.items()):
        owner = gh["owner"]
        if owner["type"] != "Organization" or owner["login"].lower() in IGNORED_ORGS:
            continue
        if path in repos:
            if not repos[path]["mirror"]:
                print(f"{path}: exists on the forge as a regular repo; not mirroring")
            continue
        forge_owner = ensure_org(owner["login"], orgs)
        act(f"{path}: creating pull mirror as {account}", forge, "POST", "/repos/migrate", {
            "clone_addr": f"https://github.com/{gh['full_name']}.git",
            "auth_username": "oauth2",
            "auth_password": TOKENS[account],
            "repo_owner": forge_owner,
            "repo_name": gh["name"],
            "mirror": True,
            "private": True,
            "service": "git",
            "description": gh.get("description") or "",
        }, timeout=3600)


def protect_mirrors(repos):
    for repo in repos:
        name = repo["full_name"]
        if not repo["mirror"]:
            continue
        if not DRY:
            try:
                forge("PATCH", f"/repos/{name}", {"enable_prune": False})
            except HTTPError as e:
                print(f"{name}: could not disable pruning: {e}")
        if repo["owner"]["login"].lower() == OWNER:
            for m in forge("GET", f"/repos/{name}/push_mirrors"):
                act(f"{name}: GitHub-canonical; removing push mirror {m['remote_address']}",
                    forge, "DELETE", f"/repos/{name}/push_mirrors/{m['remote_name']}")


def adoptable(github, forge_name, gh_name):
    for branch in pages(github, f"/repos/{gh_name}/branches", 100):
        try:
            forge("GET", f"/repos/{forge_name}/git/commits/{branch['commit']['sha']}")
        except HTTPError as e:
            if e.status != 404:
                raise
            print(f"{forge_name}: GitHub branch {branch['name']} is not on the forge; "
                  "not adding a push mirror")
            return False
    return True


def sync_push_mirrors(repos):
    github = github_client(TOKENS["default"])
    try:
        login = github("GET", "/user")["login"]
    except HTTPError as e:
        print(f"default GitHub token rejected ({e}); skipping push mirrors")
        return
    if login.lower() != OWNER:
        print(f"default GitHub token is {login}, not {OWNER}; skipping push mirrors")
        return
    owned = [r for r in repos if r["owner"]["login"].lower() == OWNER]
    pushes = {r["full_name"]: forge("GET", f"/repos/{r['full_name']}/push_mirrors")
              for r in owned}
    taken = {m["remote_address"].lower() for ms in pushes.values() for m in ms}
    for repo in owned:
        name = repo["full_name"]
        if repo["mirror"] or repo["archived"] or repo["empty"] or pushes[name]:
            continue
        gh_name = f"{OWNER}/{repo['name']}"
        target = f"ssh://github.com/{gh_name}.git"
        if target.lower() in taken:
            print(f"{name}: {target} is already push-mirrored by another repo")
            continue
        try:
            github("GET", f"/repos/{gh_name}")
        except HTTPError as e:
            if e.status != 404:
                raise
            if not act(f"{name}: creating GitHub repo {gh_name}", github, "POST",
                       "/user/repos", {"name": repo["name"], "private": repo["private"]}):
                continue
        else:
            if not adoptable(github, name, gh_name):
                continue
        mirror = act(f"{name}: adding push mirror to {target}", forge, "POST",
                     f"/repos/{name}/push_mirrors", {
                         "remote_address": target,
                         "use_ssh": True,
                         "sync_on_commit": True,
                         "interval": MANIFEST["push_mirror_interval"],
                     })
        if not mirror:
            continue
        if act(f"{name}: registering deploy key on {gh_name}", github, "POST",
               f"/repos/{gh_name}/keys", {"title": "forgejo push-mirror (spark)",
                                          "key": mirror["public_key"], "read_only": False}):
            act(f"{name}: triggering first push", forge, "POST", f"/repos/{name}/push_mirrors-sync")


def sync_actions(repos):
    for repo in repos:
        want = repo["full_name"].lower() in ACTIONS
        if repo["archived"] or repo["has_actions"] == want:
            continue
        act(f"{repo['full_name']}: has_actions -> {want}", forge, "PATCH",
            f"/repos/{repo['full_name']}", {"has_actions": want})


def main():
    gh_repos = github_repos()
    repos = {r["full_name"].lower(): r for r in pages(forge, "/repos/search", 50, "data")}
    orgs = {o["username"].lower(): o["username"] for o in pages(forge, "/admin/orgs", 50)}

    sync_pull_mirrors(gh_repos, repos, orgs)
    current = list(pages(forge, "/repos/search", 50, "data"))
    protect_mirrors(current)
    sync_push_mirrors(current)
    sync_actions(current)
    return 0


if __name__ == "__main__":
    sys.exit(main())
