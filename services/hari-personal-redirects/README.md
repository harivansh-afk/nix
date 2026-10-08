# Personal domains

Vercel project `hari-personal-redirects`, in `rathiharivansh-gmailcoms-projects`.

`hari.cafe` and `www.hari.cafe` proxy the live site at `https://harivan.sh`, including paths and assets. Visitors keep the cafe hostname. DNS and TLS stay at Vercel; Spark remains the site origin. Other domains retain their existing redirects to `harivan.sh`.

Deploy from this directory with the owner's Vercel CLI login:

```sh
vercel link --project hari-personal-redirects --scope rathiharivansh-gmailcoms-projects --yes
vercel deploy --prod --yes
```

Verify both cafe hostnames return 200 without a Location header, and check an article and a hashed asset. Check `hari.ink` still returns its original 308 redirect.
