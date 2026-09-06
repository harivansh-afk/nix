# VoiceInk settings

`settings.json` is applied by `hosts/macbook/voiceink/settings.nix` during
`just switch`. Quit VoiceInk before switching and reopen it afterward so its
in-memory preferences do not overwrite the applied values.

`preferences` holds ordinary macOS defaults. `jsonData` holds the model list,
Modes, and recording shortcut; VoiceInk reads these as JSON-encoded Data,
so activation writes them with `defaults -data`, not as strings or dictionaries.
The listed settings are reapplied on every switch. After changing them in the
app, update this file to keep the change. Unlisted preferences, credentials,
recordings, history, and downloaded models remain app-managed.
The existing onboarding-completion flags are preserved because VoiceInk's
first-launch migration otherwise clears the restored Modes. macOS microphone
and Accessibility permissions still need to be granted on a new machine.

The default mode uses Whisper Large V3 on Spark, English, live transcription,
and paste output without AI enhancement. The recorder floats in mini style.
The recording shortcut is Fn in hybrid mode; audio uses the built-in microphone,
pauses media, and plays the selected start/stop sounds.

VoiceInk 2.13 supports local streaming through FluidAudio and several hosted
providers, but has no streaming provider for custom cloud endpoints. Spark's
Whisper backend therefore still needs `streaming-provider.patch` and the
WebSocket adapter in `hosts/spark/services/whisper/server.py` for live text.
Removing them requires either disabling real-time transcription and submitting
the recording after stopping, or choosing a different supported provider.
The built-in Parakeet and Nemotron options run on the Mac, not on Spark.

`dictionary.json` is a separate import asset; this settings module does not
install it into VoiceInk's database.
