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
