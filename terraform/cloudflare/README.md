# Cloudflare DNS

`records.nix` declares DNS for `harivan.sh` and `hari.cafe`. Records default to
`harivan.sh`; set `zone` for another zone. `config.nix` renders these records
through terranix, and the `cloudflare-dns` wrapper runs OpenTofu.

State is tracked in `state/terraform.tfstate`; commit state changes after an
apply or import so the next checkout uses the same resource IDs. The provider
lock is tracked too. Generated configuration and provider downloads are ignored.

## Credentials

The wrapper reads `CLOUDFLARE_API_TOKEN` from the environment, falling back to
`/run/secrets/cloudflare-api-token`. The encrypted source is
`secrets/user/cloudflare-api-token`; the token never enters the Nix store.

Scope the token to both managed zones. Planning needs `Zone:Read` and
`DNS:Read`; applying also needs `DNS:Edit`. To replace it:

```sh
just sops-edit secrets/user/cloudflare-api-token
just switch
```

## Changes

From the repository root:

```sh
just dns-init
just dns-plan
just dns-apply
```

Edit `records.nix`, review the plan, then apply and commit the updated state.
For an existing record, import its Cloudflare ID into the matching resource
address before applying; the plan should then contain only intended changes.

DNS is separate from Cloudflare Access, TLS settings and domain registration.
Changing NixOS configuration does not apply this DNS configuration.

## Bot protection

`protection.nix` turns on Cloudflare's AI crawler block, AI Labyrinth
(`crawler_protection`) and the managed robots.txt on every zone, and adds one
custom WAF rule on `harivan.sh` that puts a managed challenge in front of
Forgejo's archive, blame, commit, commits and compare pages. A second rule, on
both zones, blocks verified search, SEO and archiver crawlers on every host
except `harivan.sh`, `hari.cafe` and their `www` names. Link-preview bots
(Slack, Discord, iMessage) and monitoring (Better Stack) are other verified
bot categories and stay allowed.

Those pages render a fresh diff, blame or tarball per request, and Spark's
uplink is the bottleneck: crawlers walking every commit of every repo through
them starved draw and vault. Git over HTTPS (`info/refs`, `git-upload-pack`),
flake inputs and release downloads do not match the rule. A browser solves the
challenge once; scripted `curl` of an archive URL gets a 403.

Bot Fight Mode stays off. On the Free plan it cannot be skipped per path, and
it challenges Bitwarden apps, git clients and draw's API polling.

Applying needs the token to also hold `Zone WAF:Edit` and
`Bot Management:Edit` (shown as "Zone > Bot Management") on both zones. If a
zone already has a custom-firewall entrypoint ruleset from the dashboard, the
apply fails with a conflict; import it first:

```sh
tofu import cloudflare_ruleset.sh_custom_firewall zones/<zone_id>/<ruleset_id>
tofu import 'cloudflare_bot_management.sh' <zone_id>
tofu import 'cloudflare_bot_management.cafe' <zone_id>
```
