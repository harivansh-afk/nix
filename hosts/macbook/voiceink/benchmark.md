# Dictation measurements — 2026-10-07

Recommendation: keep local Parakeet V3 and use Spark for correction review.
Leave per-dictation AI Enhancement off by default; enable it when the writing
cleanup is worth the additional wait. Learned replacement rules are applied
locally before optional enhancement, so they do not require a model call on
every paste.

## Setup and scope

- Mac: Apple M4, 16 GiB, VoiceInk source revision
  `640b0c8c36ee74d9e76d930f40e2c04bb739b4b3` (v2.21 tag; bundle says 2.20).
- Native harness: exact FluidAudio revision
  `762baf6733ca0f0dbeb1ce335363fc75066bd2c9`, Parakeet V3 int8,
  English, default ASR config, VAD threshold 0.7. The streaming harness uses
  VoiceInk's copied provider and word-agreement engine, with paced PCM replay.
- Spark: NVIDIA GB10. Existing Whisper Large v3 service, plus a temporary
  Ollama 0.30.7/CUDA 13 server running `qwen3:8b`, thinking disabled,
  temperature 0.3 and 8192-token context. All 37 layers offloaded to CUDA.
- Eleven saved recordings, 1.7–97.0 seconds each, 261.8 seconds total.
  Same audio used for both recognizers; two batch passes each. Five recordings
  replayed at realtime pace through each streaming path, plus digital silence.
  Three representative recordings also ran through the combined streaming +
  cleanup pipeline. No private audio or full transcripts are included here.
- Cleanup uses the draft's actual prompt inside VoiceInk's full system template.
  Mac requests travel over Tailscale HTTPS, Caddy, and Ollama. Small HTTPS
  requests took 26–32 ms, excluding curl process startup.

These are small-sample engineering measurements, not an ASR accuracy benchmark.
Saved ASR transcripts are not verified human references, so no WER is claimed.
The native harness excludes actual microphone capture and UI/paste delivery.
One Whisper+cleanup replay overlapped a stress test; that sample was rerun
without contention and only the isolated result is shown below.

## After-Stop latency

Seconds from the end of paced audio input until final text is available.
Model setup and the recording itself are excluded. This is not full GUI
stop-to-paste timing. These are individual representative runs, not percentiles.
The one saved real-app Parakeet entry in the selected history recorded 2.23
seconds of transcription time; its warm/cold state is unknown. The controlled
warm replay below is not evidence that all real-app latency is already that low.

| Recording duration | Mac Parakeet | Parakeet + Spark cleanup | Spark Whisper | Whisper + Spark cleanup |
|---|---:|---:|---:|---:|
| 1.7 s | 0.09 | 0.83 | 0.59 | 1.16 |
| 14.8 s | 0.14 | 1.68 | 1.93 | 3.43 |
| 30.0 s | 0.23 | 3.33 | 0.87 | 4.17 |

Across all five recorded-audio streaming replays, raw Parakeet finished in
0.09–0.45 seconds after Stop. Live previews ran, but every replay selected
VoiceInk's native batch fallback because it had fewer than three confirmed
segment events. No PCM chunks were dropped. The corresponding Whisper range
was 0.40–1.93 seconds; low latency did not imply a correct transcript.

For the full eleven-recording **batch** comparison, warm median time was
0.067 seconds for Parakeet and 2.04 seconds for the existing Whisper endpoint.
These full-file processing times must not be confused with streaming finalization.

## Cleanup cost and quality

- Warm cleanup of a short reply: about 0.5 seconds.
- A roughly 100-word Parakeet transcript: 3.18 seconds in one warm run.
- The longest Parakeet transcript, 265 words: 7.41 seconds.
- First request after starting/loading Qwen: 17.72 seconds, including
  15.84 seconds of model load time.
- A deliberate unload/reload of the same 52-word request: 6.39 seconds,
  versus 1.62 seconds warm. This simulates the configured idle eviction more
  closely than the first-ever load, but is only one reload sample.
- The standalone Mac runner's initial model/VAD setup took 16.23 seconds;
  this is separate from warm per-dictation timings and not a measured app launch.

Parakeet returned empty output for digital silence and low-amplitude synthetic
noise. On the known failing recording, it returned the opening phrase without
inventing a sign-off. The existing Whisper streaming path repeated “Thank you”
on pure silence and the known failing recording. Batch Whisper produced a
repeated invented sentence; AI cleanup reduced it to one invented sentence.
A tidy result is therefore not proof that the audio was recognized correctly.

Cleanup improved punctuation in several samples, but did not reliably resolve
unfamiliar technical names or remove every filler. It cannot recover acoustic
information from text alone. Vocabulary hints and replacement rules remain
important.

A synthetic three-correction review returned valid JSON, learned a phonetic
personal-name correction, and rejected a date change. It also learned a common
technology spelling despite the upstream prompt saying not to do so. This is
an over-learning example, not evidence of perfect correction classification.
Real Accessibility capture and persistence still require an in-app acceptance test.

## Contention and production fixes

A 20-correction synthetic backlog was submitted 0.3 seconds before a normal
52-word cleanup request. With one slot and otherwise idle inference:

| Ollama slots | Review batch | Cleanup waiting alongside review | Reported model/GPU memory |
|---|---:|---:|---:|
| 1 | 18.07 s | 19.24 s | 6.30 GB |
| 2 | 19.03 s | 2.59 s | 7.50 GB |

With additional Whisper activity, the one-slot cleanup request reached 20.85
seconds, beyond the proposed 20-second timeout. Two slots reduce queueing;
they do not make rewriting free or guarantee tail latency. Model memory above
is Ollama's reported allocation, not total service RSS or a full memory-cap test.

Direct Tailscale Serve → loopback-bound Ollama returned HTTP 403 because of
Host validation. The tested working path uses Caddy with an explicit upstream
`Host: 127.0.0.1:<ollama-port>`. The deployment config now includes that proxy.
The Mac reached version and inference endpoints through the tested Tailscale
HTTPS route; the model list was checked on Spark.

No system deployment or live VoiceInk preference change was performed. Temporary
servers, model weights, copied audio and Mac build scratch are cleaned up after
measurement. Small reproduction scripts and detailed results remain privately
on Spark; original Mac recordings and installed models are not removed.

Cleanup completed: the 5.2 GB temporary model download, 913 MiB of Mac test
scratch, copied recordings, and both temporary servers were removed. The test
Tailscale port was disabled. About 0.3 MB of private results/scripts remain;
normal Nix package build cache is retained for the intended deployment.
