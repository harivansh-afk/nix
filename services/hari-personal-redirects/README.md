# Personal domains

Vercel project `hari-personal-redirects`, in `rathiharivansh-gmailcoms-projects`.

These domains 308 to `harivan.sh`. `hari.cafe` is registered here but no longer served here: its nameservers are Cloudflare's, and Spark serves it directly (see `hosts/spark/services/website.nix` and `terraform/cloudflare`).

Deploy from this directory with the owner's Vercel CLI login:

```sh
vercel link --project hari-personal-redirects --scope rathiharivansh-gmailcoms-projects --yes
vercel deploy --prod --yes
```

Check `hari.ink` still returns its 308 redirect.
