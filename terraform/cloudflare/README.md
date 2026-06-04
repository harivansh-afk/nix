# Cloudflare DNS for harivan.sh

Declarative DNS for the `harivan.sh` zone. Records are defined in Nix
(`records.nix`), rendered to `config.tf.json` by terranix, and applied with
OpenTofu through the `cloudflare-dns` flake app.

```
records.nix  ->  terranix  ->  config.tf.json  ->  tofu plan/apply
```

State is checked in under `state/terraform.tfstate` so a fresh checkout is in
sync without re-importing. The API token never touches the Nix store or the
repo; it is read from `CLOUDFLARE_API_TOKEN` at runtime.

## Files

- `records.nix` - the single source of truth: `zoneId`, the tunnel target,
  and the record set.
- `config.nix` - terranix module: provider, local backend, and the
  `cloudflare_dns_record` resources generated from `records.nix`.
- `state/terraform.tfstate` - committed state.

## Token (SOP)

The Cloudflare provider reads `CLOUDFLARE_API_TOKEN`. The `cloudflare-dns`
runner resolves it automatically, in this order:

1. `CLOUDFLARE_API_TOKEN` from the environment (one-off / CI override).
2. The sops secret at `/run/secrets/cloudflare-api-token` (the normal path).

So `just dns-plan` works with no manual `export` once the secret is in sops
and the host has been switched. If neither source is present the runner exits
with an explicit message instead of a confusing provider error.

### Token scopes

- `dns-plan` (and the one-time backfill) only need a **read-only** token:
  `Zone:Read` + `DNS:Read`, scoped to `harivan.sh`. It cannot modify the zone.
- `dns-apply` needs an **edit** token: `DNS:Edit` + `Zone:Read`. Use one edit
  token for both and you never think about it again.

### Set or rotate the token (the SOP)

The token lives in sops (`secrets/user/cloudflare-api-token`, user bucket, so
it decrypts on both macbook and spark). To set or rotate it:

```
# 1. Mint a token in the Cloudflare dashboard (My Profile -> API Tokens).
#    For full plan+apply: DNS:Edit + Zone:Read, scoped to harivan.sh.
# 2. Store it (replaces the existing value):
just sops-edit secrets/user/cloudflare-api-token
# 3. Apply so it lands at /run/secrets/cloudflare-api-token:
just switch          # on the host you run dns from
# 4. Verify:
just dns-plan        # no manual export needed
```

The token never touches the Nix store or git in plaintext; sops keeps it
encrypted at rest and the runner reads the decrypted copy from `/run/secrets`
at runtime.

> The value currently committed is a read-only backfill token that was once
> pasted in chat. Rotate it (steps above) to an edit-capable token before the
> first `dns-apply`, and revoke the old one in the Cloudflare dashboard.

## Backfill (one-time, aligning Nix with the live zone)

The goal: make `records.nix` reproduce the live zone exactly, import the
existing records into state, and confirm `tofu plan` reports **no changes**.
Nothing is written to Cloudflare during this phase.

1. Dump the live zone (read-only token) to discover `zoneId` and every record
   with its id, name, type, content, proxied flag, ttl, and any priority.
2. Edit `records.nix` to match the dump exactly; set `zoneId`.
3. `nix run .#cloudflare-dns -- init`
4. Generate `import {}` blocks (one per record, address -> Cloudflare record
   id) and run `nix run .#cloudflare-dns -- plan -generate-config-out=tmp.tf`
   to confirm the generated config matches, or `tofu import` each record.
5. `nix run .#cloudflare-dns -- plan` MUST print `No changes`. If it does not,
   `records.nix` does not yet match the live zone; fix and repeat. Do not
   apply until the plan is a no-op.
6. Commit `state/terraform.tfstate`.

## Day-to-day

Add or change a subdomain by editing `records.nix`, then:

```
nix run .#cloudflare-dns -- plan    # review
nix run .#cloudflare-dns -- apply   # needs an edit-capable token
```

Use `-auto-approve` when running non-interactively.
