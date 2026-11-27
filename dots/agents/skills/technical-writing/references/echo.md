# Echo workflow

The local provider instructions are `~/echo.md`. Read API details as needed,
but treat its credential as a secret: never print the file, include it in a
prompt or copy it into the repository or Nix store. Use `SLASHY_API_KEY` from
the environment. If necessary, load the key privately from the local file
inside the calling process without placing it in command arguments or logs.

The helper uses the documented OpenAI-compatible endpoint
`https://api.slashy.com/v1/chat/completions`, model `echo`, default sampling
settings and a 600-second timeout. Requests can take minutes on a cold start.
Run it in a background tool session and keep the user informed while waiting.
The documented context limit is 32,768 tokens and the output limit is 4,096.
Keep the brief and samples comfortably within those limits; split long work
at real section boundaries.

```sh
uv run --no-project python <skill-directory>/scripts/echo.py \
  --prompt <private-artifact-directory>/prompt.md \
  --output-dir <private-artifact-directory>/attempt-1
```

The output directory must be new. The helper stores the submitted prompt,
raw JSON response and completed prose there. It preserves truncated output
as `partial.md` and exits unsuccessfully, so it cannot pass silently as a
finished draft. It does not retry paid requests automatically. On a transient
failure, retry at most once in a new directory, respecting Retry-After on
rate limits. If it still fails, retain the evidence and report the failure.

After generation, review the draft against the brief before applying it.
Keep the provider response unchanged as provenance and save the edited
manuscript separately. Local artifact availability does not imply publication
or permission to upload those files elsewhere.
