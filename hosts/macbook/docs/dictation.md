# Dictation trial

Superwhisper is installed by Homebrew on the next Mac `just switch`. Open
`/Applications/superwhisper.app` manually and finish its microphone and
Accessibility onboarding. Keep launch at login off during the trial.

Quit VoiceInk while testing so the recording shortcuts do not compete.
VoiceInk and its Spark backend remain available as the fallback.

Start with English, the local **Parakeet** voice model, and realtime
transcription enabled. Use plain transcription without AI rewriting first.
Check ordinary messages, technical names, a long thinking pause, and silence.
Then try **Cohere Transcribe** if fewer corrections matter more than seeing
words while speaking; Cohere does not support realtime transcription.

For local English cleanup, **Message** mode with **S1-mini** is supported.
Check that it preserves wording and intent before making it the default.
Other language models may send transcripts to a cloud provider.

Parakeet, Cohere, realtime, and AI processing require Pro. New accounts get
3,000 words of Pro trial use, then fall back to the free local Whisper tier.
This configuration does not purchase or activate a license. Current monthly
pricing is $8.49; verified students can request 40% off before buying.

Superwhisper supports vocabulary and replacements. Automatic observation and
learning of edits, as implemented by VoiceInk 2.21, was not established by the
reviewed documentation. Do not treat switching apps as delivering that feature.

After the trial, choose the daily app before removing VoiceInk, its source
build, or the Spark service. Do not remove the Superwhisper cask casually:
this repo uses Homebrew `cleanup = "zap"`, which can delete its local data.

Sources: [models](https://superwhisper.com/docs/models/voice),
[local cleanup](https://superwhisper.com/docs/models/language),
[plans](https://superwhisper.com/docs/billing/plans),
[benchmark methodology](https://superwhisper.com/benchmarks).
