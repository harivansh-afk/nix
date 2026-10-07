# VoiceInk

The flake builds VoiceInk 2.21 from source, preserving the custom streaming
provider and compact recorder patches. `make local` produces a Release app.
The existing stable signing identity and disabled Sparkle updates remain in use.

After switching the Mac, quit and reopen VoiceInk. In **AI Models**, download
**Parakeet V3** once. The default mode selects it for local dictation; the model
files live in VoiceInk's mutable cache, outside the Nix store. Dictation with this
mode requires that download. The old Spark Whisper provider remains available
but is no longer the default: its streaming endpoint produced repeated
"Thank you" from digital silence during diagnosis.

Dictionary Auto Learn uses **Ollama on Spark**, with `qwen3:8b` selected.
The Mac does not run the language model. Auto Learn reviews edits immediately
and stores reusable vocabulary/replacements in VoiceInk's local dictionary.
Replacement rules apply locally without waiting for AI on each dictation.
This does not retrain Parakeet or guarantee recognition accuracy.

Per-dictation **AI Enhancement is off by default** after measuring its latency.
The default mode has the same Spark provider and a conservative cleanup prompt
ready to select when desired. See [the benchmark](benchmark.md) for timings.

Deploy Spark first with `just switch-spark`. Its `ollama-model-loader` service
downloads the model in the background; wait for it to finish before switching
the Mac. Ollama binds to `127.0.0.1:18434` and Tailscale Serve exposes
`https://spark-ix.tail368802.ts.net:18443` within the tailnet. A Caddy listener
on `127.0.0.1:18435` sets the upstream Host header that Ollama requires;
direct Tailscale proxying returns HTTP 403. The service uses CUDA, disables
Ollama cloud, permits one loaded model with two simultaneous requests, and
unloads the model after five idle minutes. Two slots prevent background review
from monopolizing optional cleanup. The separate large vLLM experiment remains
manual-start.

After the Mac switch, quit and reopen VoiceInk. In **AI Models → Ollama**, verify
the Spark URL above and `qwen3:8b`. To try optional cleanup, enable **Modes →
default → AI Enhancement**; the provider is Ollama and the prompt is
**Dictation cleanup**. In **Dictionary
→ settings → Auto Learn**, verify the same provider/model and **Immediately**.
The old Spark Whisper chat-completions URL is an echo endpoint and must not be
used for enhancement or correction review.

Before relying on it, check `curl http://127.0.0.1:18434/api/tags` on Spark,
the HTTPS `/api/tags` URL from the Mac, then a real cleanup and an edited name
that creates the intended dictionary entry. Check `ollama ps` with
`OLLAMA_HOST=http://127.0.0.1:18434` to confirm GPU offload. The first request
after unloading is slower. Enhancement has a 20-second timeout without an
automatic retry; upstream preserves the raw transcript if enhancement fails.
If Spark/Tailscale is unavailable, review cannot run. Plain Parakeet
transcription still needs no Spark connection when AI Enhancement is disabled.

Check silence, a long pause, ordinary speech, and technical names before relying
on the new model. Model accuracy and Accessibility correction capture need
testing in the actual target applications.

`nix build .#checks.aarch64-linux.voiceink-patches` verifies both patches against
the pinned upstream source. It does not compile the macOS app; `just switch` on
the Mac performs that build.
