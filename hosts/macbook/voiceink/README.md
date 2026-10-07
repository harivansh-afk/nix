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

AI Enhancement and Dictionary Auto Learn use **Ollama on Spark**, with
`qwen3:8b` selected for both. The Mac does not run the language model. The
dictation mode uses a conservative cleanup prompt; Auto Learn reviews edits
immediately and stores reusable vocabulary/replacements in VoiceInk's local
dictionary. This does not retrain Parakeet or guarantee recognition accuracy.

Deploy Spark first with `just switch-spark`. Its `ollama-model-loader` service
downloads the model in the background; wait for it to finish before switching
the Mac. Ollama binds to `127.0.0.1:18434` and Tailscale Serve exposes
`https://spark-ix.tail368802.ts.net:18443` within the tailnet. It uses CUDA,
disables Ollama cloud, permits one loaded model/request at a time, and unloads
the model after five idle minutes. The separate large vLLM experiment remains
manual-start.

After the Mac switch, quit and reopen VoiceInk. In **AI Models → Ollama**, verify
the Spark URL above and `qwen3:8b`. In **Modes → default → AI Enhancement**, the
provider should be Ollama and the prompt **Dictation cleanup**. In **Dictionary
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
