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

## Token

The Cloudflare provider reads `CLOUDFLARE_API_TOKEN`.

- Backfill and verification (dump, import, plan) only need a **read-only**
  token: `Zone:Read` + `DNS:Read`, scoped to `harivan.sh`. A read-only token
  cannot modify the zone, so the entire alignment phase is safe by
  construction.
- Applying changes needs `DNS:Edit` (and `Zone:Read`).

```
export CLOUDFLARE_API_TOKEN="$(cat ~/cf-token)"
```

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
