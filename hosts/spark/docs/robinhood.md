# Robinhood MCP

The personal `desktop` and `imessage` Hermes profiles connect directly to
`https://agent.robinhood.com/mcp/trading`. The root/default and roommates profiles
do not declare Robinhood. The Mac desktop app uses the Spark backend, so this
requires a Spark deployment rather than a Mac rebuild.

`hosts/spark/services/hermes/default.nix` owns the server declaration and personal
toolsets; `desktop.nix` reuses that declaration. Robinhood advertises the `internal`
OAuth scope and dynamic client registration. `oauth.cimd = false` selects that
registration flow, as with Beeper. The server exposes both read and trading tools;
registering it does not place orders or authorize autonomous trading.

The Photon conversation plugin exposes account, portfolio, position and quote
reads directly for quick questions. Other Robinhood tools remain available to
native delegated workers, as with other longer personal-assistant tasks.

## Authorize after deployment

Run on Spark, one profile at a time:

```sh
hermes --profile desktop mcp login robinhood
hermes --profile imessage mcp login robinhood
```

Each command prints a Robinhood authorization URL. Complete sign-in and consent
in the browser. Each profile has its own grant; the existing Codex login is not
reused. Hermes stores tokens under that profile's `mcp-tokens/` directory in
`~/.local/state/hermes/.hermes/profiles/`. Tokens and client registration files
are mutable runtime state, never Nix values or Git files.

If signing in on the Mac, forward the callback port shown in the authorization
URL to Spark before finishing consent. In another Mac terminal, replace `PORT`
with that port:

```sh
ssh -N -L 127.0.0.1:PORT:127.0.0.1:PORT spark
```

The browser can then deliver the localhost callback directly to Hermes on Spark.
Keep the login command and tunnel running until authorization succeeds, then
close the tunnel. The next profile may select a different callback port. Do not
put authorization codes or complete callback URLs into docs, logs or Git.

## Verify

```sh
hermes --profile desktop mcp test robinhood
hermes --profile imessage mcp test robinhood
```

Both tests must connect and discover tools. Then start a fresh Desktop session
with the `desktop` profile selected and ask for account/portfolio data. Verify a
read-only request through iMessage independently. A configuration entry or OAuth
success alone does not prove the running agent can use the tools.
