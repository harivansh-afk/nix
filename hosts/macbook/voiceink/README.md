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

Dictionary Auto Learn is enabled, with **Ollama** selected separately from the
dictation mode and review set to **manual**. Connect a local Ollama instance and
select its model under **Dictionary → Auto Learn** before reviewing corrections.
This PR does not install Ollama or download a reviewer model. After verifying a
real correction creates the intended vocabulary/replacement entry, change
`AutoLearnDictionaryReviewSchedule` to `immediately` in
`dots/voiceink/settings.json` for automatic review across rebuilds. VoiceInk
Refine can clean up writing but cannot serve as the Auto Learn reviewer.

Check silence, a long pause, ordinary speech, and technical names before relying
on the new model. Model accuracy and Accessibility correction capture need
testing in the actual target applications.

`nix build .#checks.aarch64-linux.voiceink-patches` verifies both patches against
the pinned upstream source. It does not compile the macOS app; `just switch` on
the Mac performs that build.
