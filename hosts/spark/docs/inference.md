# Local inference: Qwen Flash Next on vLLM

`hosts/spark/services/inference.nix` replaces the llama.cpp router with the
single-Spark Qwen3.8-Flash-Next NVFP4 recipe. The API remains
`http://127.0.0.1:18080/v1`; the model ID becomes `qwen3.8-flash-next`.
OMP's local main and task roles use that model. Hermes's separate `spark`
provider changes with it; Hermes's cloud default stays on Astra.

## Reproducible inputs

- Recipe: [MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark](https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark),
  commit `d03809008834124e80223c3482f2ddb59577a48f`.
- ARM64 base image: `docker.io/vllm/vllm-openai@sha256:3b0e188ffceb3d07e09c3cb5215433a0020eacf02d7f882ed3a8bfd15454477e`.
- Model: `Mia-AiLab/Qwen3.8-Flash-Next-NVFP4`,
  revision `925d7be6c14c6c9442ef83e8f05b5a3c39304f69`.

Nix fetches the recipe with a content hash and builds the image context.
`vllm-prepare.service` builds the Podman image from that context, downloads the
pinned public model, and builds its packed PLE table. The image tag is derived
from the base-image digest and Nix build-context path. Patches run during image
build and fail if their source anchors no longer match. Nothing patches a
running container or installs Python packages at service startup.

The patched files implement NVFP4 PLE loading, memory-mapped PLE CPU offload
and GB10 synchronization, MXFP8 fallback, FP8 sparse-attention KV handling, and
reduced-vocabulary MTP drafting. The recipe and its AGPL license are retained
in the image at `/opt/spark-recipe`.

`inference/model-files.json` records filenames and byte lengths from the pinned
Hugging Face revision's API (`?blobs=true`), excluding README and .gitattributes.
When updating the model revision, regenerate that manifest from the same
revision. Preparation refuses incomplete or truncated checkpoints. Hugging
Face manages downloads; file-size checks are completeness checks, not an
independent full-file cryptographic verification.

## First experiment

The initial profile is native 65,536-token context, one sequence, 2,048-token
prefill chunks, FP8 KV, BF16 recurrent state, MTP with three draft tokens, and
a full decode graph for the resulting four-token verification width.
GPU utilization is capped at 0.70, approximately 85 GiB of Spark's 121 GiB
pool. These are conservative trial settings, not a reproduced performance
result. They intentionally differ from the author's 512k benchmark profile.

Preparation checks free space before pulling or downloading: missing model
bytes, a conservative 35 GiB allowance for an absent runtime image, 28 GiB
for an absent packed table, and a 20 GiB free-space floor. The image allowance
is an estimate. Prepared artifacts are credited on subsequent starts.
On 2026-09-12 the host had approximately 90 GiB free before image validation;
this is insufficient for initial preparation. Resolve storage before merging
and activating this replacement: activation disables the old server even if
vLLM preparation refuses to proceed.

After activation, inspect the preparation and serving units separately:

```sh
systemctl status vllm-prepare podman-vllm vllm-memory-watch
journalctl -u vllm-prepare -u podman-vllm -u vllm-memory-watch -f
curl --fail http://127.0.0.1:18080/health
curl --fail http://127.0.0.1:18080/v1/models
```

`podman-vllm` being active means the container started, not that the model is
ready. Require `/health` before sending work; the upstream cold start took
about 11 minutes. A first image/model preparation can take much longer.
A start that fails its preflight can be retried with
`sudo systemctl start podman-vllm` after resolving the condition. A failed
preparation can be retried through `sudo systemctl restart vllm-prepare`.

The service uses GPU CDI with Podman, host networking with an explicit
loopback bind, private IPC with 2 GiB shared memory, and read-only model/table
mounts. Private IPC differs from upstream's host IPC; multiprocessing shares
one container IPC namespace, and stopping it does not leave segments in the
host's `/dev/shm`. Verify the PLE handshake during the first GPU launch.

Before declaring the replacement usable, exercise ordinary and streaming
chat, a tool call and its result round trip through OMP/Hermes, cancellation,
a fresh long prompt, and a follow-up reusing the prefix. Record cold startup,
time to first token, decode tokens/sec, and host memory under the normal
service load. The old 27B baseline was one 256-token request at 10.8 tok/s;
the recipe's reported 48.7 tok/s is not a prediction for this profile.
OMP advertises text input until image handling is verified end to end.

## Memory and lifecycle

vLLM stays resident. The container's host-memory ceiling is 94 GiB with no
additional swap allowance. GPU allocations on this unified-memory platform
are not reliably bounded by cgroups, so that ceiling is not the whole guard.
Startup requires 98 GiB `MemAvailable`. A host watchdog stops the systemd
service after five one-second samples with either:

- `MemAvailable < 10 GiB`, or
- `MemFree < 3 GiB` while `MemAvailable < 14 GiB`.

The service does not restart itself after failure or a watchdog stop.
A userspace watchdog cannot guarantee protection against a rapid driver
allocation burst. Check the kernel journal for `NV_ERR_NO_MEMORY`; don't
raise GPU utilization or concurrency until measured headroom supports it.
The recipe's global VM sysctl changes are not applied: its own notes warn
that they change memory accounting and need separate measurement.

## Change and rollback

Tune the profile in `inference.nix`, then rebuild through the normal Nix
workflow. Do not edit a container, live environment file, or generated image.
All mutable artifacts live under `/var/lib/vllm`; no weights enter the Nix
closure. Preparation is CPU-only; serving owns GPU residency.

The old GGUFs under `/var/lib/llama-cpp` are retained. Revert this PR through
the normal rebuild workflow to restore the old server and client model IDs.
Do not run both servers on port 18080 or assume their model memory fits
together. No existing weights are deleted by this change.

## Checks without model loading

```sh
nix build .#nixosConfigurations.spark.config.system.build.vllmImageContext --no-link
nix build .#checks.aarch64-linux.vllm-preparation .#checks.aarch64-linux.spark-invariants --no-link
```

`system.build.vllmPreparation` exposes the generated preparation JSON for
inspection. The resource-guard tests cover missing/truncated files, incomplete
packed tables, disk refusal before downloads, and the watchdog's debounce and
service-stop behavior. Building the image verifies patch application and
Python syntax without downloading model weights or touching the GPU.
