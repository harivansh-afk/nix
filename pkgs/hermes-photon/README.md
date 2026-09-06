# Photon threaded replies

Local patch against the locked `NousResearch/hermes-agent` input. Nix owns the
installed gateway package and separately assembled Node sidecar; there is no
Hermes source fork configured in this flake. Apply the patch to both from one
plugin tree, without changing the upstream pin or SDK dependencies. Do not patch
mutable runtime state or only the Python adapter: the old Node normalizer already
discarded the newly authored reply body before Python saw it.

The sidecar normalizer is extracted into an importable module so regression tests
execute the same function used by the stream, rather than inspecting source text
or emulating normalization. The SDK's `reply.content` becomes the wire content;
`reply.target` becomes a separate `replyTarget` id/text preview. Quoted media is
never read, target chains are never followed, and quoted text is not passed to
mention matching or substituted for the new body. Python maps the preview to the
existing gateway reply-context fields. Only the adapter's sent-id cache proves
bot ownership; SDK `outbound` direction merely identifies the account.

Limits: 16 content levels, 128 content nodes, a shared inline-media byte budget
using the existing `PHOTON_MAX_INLINE_ATTACHMENT_BYTES` cap, and a separate
128-node quote-preview traversal with at most 2,000 text characters. Missing and
SDK stub targets do not block delivery. Unknown-size media still has to be read
before its byte size can be checked, as in upstream; this does not impose an
allocation cap on the SDK's `read()` implementation.

## Verify without deployment

```sh
nix build --no-link .#nixosConfigurations.spark.config.services.hermes-agent.package.tests.photon-replies
nix build --no-link .#nixosConfigurations.spark.config.services.hermes-agent.package
```

The first command runs the canonical upstream runner in a Nix sandbox, with the
patched plugin, the real Python runtime dependencies, synthetic Node fixtures,
real NDJSON parsing and real temporary attachment cache writes. It includes reply
regressions and upstream inbound, reaction, mention and rich-link tests. It never
starts a provider connection or sends production messages. The broader upstream
Photon suite can be run against a writable copy of the patched source using
`scripts/run_tests.sh tests/plugins/platforms/photon/`.

On an upstream bump, require the patch to apply and rerun this check. Confirm both
`package/share/hermes-agent/plugins` and `PHOTON_SIDECAR_DIR` resolve to the patched
normalizer; setting `HERMES_BUNDLED_PLUGINS` in service environment alone cannot
override upstream's wrapper `--set`. Remove this patch after adopting an upstream
fix with equivalent boundary coverage. Build success is not merge, deployment,
service restart, or live iMessage acceptance.
