# Local inference

Spark serves `qwen3.8-flash-next` at `http://127.0.0.1:18080/v1` through
NixOS's Podman container module. OMP's local overlay uses it for both roles;
Hermes's optional `spark` provider uses it too. Hermes's default stays Astra.
The old GGUF files remain on disk, but llama.cpp is disabled.

## Runtime and model

The ARM64 image is built by [lancelind/qwen3.8-Flash-DGX](https://github.com/lancelind/qwen3.8-Flash-DGX/tree/a35c3cc2935dff63eea8a664509a5931b4b82ea2)
and pinned by its platform digest in `../services/inference.nix`. It contains
community Spark fixes, including memory-mapped PLE tables, Mamba/prefix-cache
fixes and exact QSA top-k. This is a patched upstream image, not stock vLLM.
There are no local patch scripts or container builds.

The standard `hf download` command stages
[RadixArk/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4/tree/7b719225242aacd3dbd3f9407468c2ee9a9d2594)
at a pinned revision under `/var/lib/vllm/models/`. The container waits for a
successful download, mounts the checkpoint read-only, and runs offline.
Compilation caches persist under `/var/lib/vllm/cache`.

The initial profile uses 64k total context, one active sequence, 2,048-token
prefill chunks, BF16 KV cache (`auto`), prefix caching and two-token MTP
speculative decoding. Piecewise CUDA graphs keep CPU PLE lookups outside
capture, following the image's recipe. GPU memory utilization is 0.80;
container memory is capped at 100 GiB with no swap. CUDA allocations are not
fully covered by that cgroup cap, and mmap pages use the same unified memory
as the GPU. These settings still require measurement on this host.

## First experiment

**Storage blocks deployment:** on 2026-09-12 the host had about 63 GiB free,
while the pinned checkpoint totals about 126 GiB. The image adds roughly
9 GiB compressed plus unpacked layers and compilation caches. Arrange space
before merging; activation downloads the model and replaces the endpoint.
No model download, GPU startup, speed or tool-calling test has been completed
for this configuration.

After deployment, follow `journalctl -fu vllm-model-download` and then
`journalctl -fu podman-vllm`. Systemd's container-active state does not mean
model-ready; check `curl -f http://127.0.0.1:18080/health` and `/v1/models`.
Verify streaming, reasoning and actual tool-call round trips through OMP and
Hermes, then measure decode speed and peak host/GPU memory during a long
prefill. Watch the other services for memory pressure. Unlike the previous
router, this runtime keeps its model resident while idle.

A failed container stays stopped. After diagnosing it, use
`sudo systemctl restart podman-vllm`; a failed download can be resumed with
`sudo systemctl restart vllm-model-download` first. Change settings in Nix and
rebuild. Rollback is reverting the migration and rebuilding; the retained
GGUFs let the former llama.cpp configuration start again.
