# Roomcast black-video investigation

## Scope and deployment

This is an investigation and prevention proposal, not a deployed playback fix.
No TV playback, remote-key commands, service restart or configuration change was
performed as part of the investigation. Read-only status queries are not proof
that a picture is visible on the television.

Nix PR [#577](https://git.harivan.sh/harivansh-afk/nix/pulls/577) merged as
`239074caf192892f819dd3c2019bd4506f17333b` and pins Roomcast
`bf448ec258957c0c8cc103fc0c8aba94ff7952dd`, merged by Roomcast
[PR #3](https://git.harivan.sh/harivansh-afk/roomcast/pulls/3).
The deployed package is
`/nix/store/sh174kab9y9ykgdfg2dvl4s1a4i9br01-roomcast-0.1.0`.
Its `relay.py`, `server.py`, `resolver.py` and `roku.py` were compared byte-for-byte
with that revision and all matched. The local Roomcast main checkout was older;
analysis used a separate worktree at the actual pinned revision.

## Incident evidence

- Silo S01E05 resolved through Cinejoy with provider label Lisbon.
- Roomcast declared `playing`; Roku reported Media Assistant, `state=play`,
  `error=false`, and an advancing position. The viewer reported a fully black
  picture with audible audio. Player activity therefore was a false positive for
  successful audiovisual playback.
- At about 255 seconds of playback, Silo's relay counters showed about 9.5 MB of
  fetched upstream data and 89 remuxed segments. Friends had about 143.7 MB at
  155 seconds and 52 segments. This contrast is consistent with an audio-only
  stream, but counters alone cannot establish stream contents or causality.
- The attempted fallback searches on Fboxtv, BingeBang and Flixer timed out. The
  journal records only `request failed (TimeoutError)`, not the stage or selector.
  These failures do not establish that all providers or sites are unavailable.
- Playback was stopped at the user's request. A subsequent system deployment
  restarted Roomcast at 19:07 UTC, after the black-picture report. The restart
  cannot explain the earlier failure; current in-memory state is not the failed
  session. The investigation did not initiate that restart.

## Fresh Silo media probe

A dedicated read-only resolver reproduced the same Silo S01E05 Lisbon source.
It never constructed a Roku controller or launched TV playback. The probe was
independently rerun by the parent investigator with the same material results:

| Candidate | Manifest advertisement | Actual first fragment, before and after remux |
| --- | --- | --- |
| Master, selected variant | 1920×1080, AVC | H.264 Main level 5.0, **2160×1080**, 8-bit yuv420p, 24fps; video track |
| Direct lower rendition | 1280×720 in master | H.264 Main level 3.2, **1440×720**, yuv420p; video track |
| Direct audio rendition | Audio playlist | AAC-LC only, no video |

The selected video is wider than advertised and uses level 5.0. This is a strong
compatibility suspect for the FHD Roku in the acceptance record; exact device
limits and on-screen causality still need a controlled model-specific test.
Remuxing retained the video's 2160×1080 dimensions and level: it did not drop
video in this sample, nor did it scale or convert it. Audio is a separate HLS
rendition, so working sound does not establish video-decoder success.

This source also supplied a standalone audio playlist among the first three
candidates, confirming that the audio-only path is not merely hypothetical.
The incident's exact selected URL and decoder state were not retained. The
leading explanation is incompatible selected video with separately working
sound; audio-only candidate selection is another demonstrated path. Neither is
claimed as conclusively proven for the original playback. The lower rendition
is a candidate for a future authorized test **within its master/audio group**,
not permission to launch the video-only child playlist as a complete episode.

## Confirmed design gaps

References below are to the pinned Roomcast revision, not the older main checkout.

### Candidate identity and media validation

`resolver.py:160-175,204-213` observes successful HLS responses and yields up to
three URLs in arrival order. It does not distinguish master manifests, video
renditions and audio renditions. It can therefore accept a media playlist that
is not a complete audiovisual presentation.

`server.py:54-67` prepares a manifest and a first child/segment. It never probes
streams, verifies the presence of video, decodes a frame, or establishes that the
video format is supported by this Roku.

`relay.py:93-105` chooses master variants by height alone. Missing resolution is
treated as zero, with no codec or audio-only rejection. `relay.py:138-192` remuxes
fragmented MP4 to MPEG-TS with `-map 0:v? -map 0:a? -c copy`. Both tracks are
optional. Audio-only input can successfully become an audio-only transport
stream, and unsupported video is copied unchanged rather than made compatible.
Successful FFmpeg exit and output size checks do not establish decodable video.

The root cause of the exact Silo stream remains subject to media-level evidence;
these code paths prove that the system has no gate to prevent that failure class.

### Success and fallback

`server.py:115-129` ends provider fallback when preparation, launch and Roku
confirmation succeed. An audio-only presentation that passes those checks is
never treated as a failed provider. This is why ordinary fallback does not repair
black-picture reports after the state has become `playing`.

The agent's previous guidance also conflated expected-app playback with success.
The companion skill change distinguishes activity confirmation from picture
confirmation and treats the viewer's report as evidence, not something that an
error-free status can rebut.

### Alternate-site search and observability

`resolver.py:73-110` uses a particular Search button, input selector and numeric
`/series/` or `/movie/` link pattern for every supplied origin. A directory entry
is discovery, not a site-specific adapter. Repeatedly feeding arbitrary directory
IDs into that same search routine is not independent provider recovery.

`server.py:24-36` intentionally avoids returning exception details, but its
server-side log retains only the exception class. FFmpeg stderr is discarded in
`relay.py:173-174`, and prefetch exceptions are swallowed in `relay.py:213-217`.
Privacy-safe diagnostics are needed rather than logging signed URLs or headers.

## Executed verification

The pinned revision's existing suite passed: `uv run --frozen python -m unittest
 discover -s tests -q` ran 39 tests. A separate synthetic offline audit was then
executed against the deployed package (no service or TV commands):

- Equal-height AVC followed by HEVC selected HEVC; selection is not codec-aware.
- Missing-resolution video followed by audio selected the audio variant.
- `Service.prepare` accepted a playlist whose segment was literally non-media
  bytes. It is a fetch/preparation check, not media validation.
- Real FFmpeg-generated audio-only fragmented MP4 remuxed successfully; ffprobe
  reported AAC audio and no video in the resulting transport stream.
- Real FFmpeg-generated High 10 H.264 remained `yuv420p10le` / High 10 after
  remuxing. Packaging conversion did not normalize video compatibility.
- A simulated browser HLS audio response arriving before provider selection was
  yielded as that provider's candidate. The first provider does not clear the
  pre-existing candidate list. Thus the provider label itself is not proof of
  which provider originally supplied a captured URL.

All offline assertions passed; these are intentionally synthetic reproductions
of defects, not recordings of the failed Silo session. They demonstrate missing
checks without claiming to prove which candidate played during the incident.
Nix formatting (`nix fmt -- --ci`) and `git diff --check` passed for this
report/guidance change. No playback fix or TV picture acceptance is claimed.

## Prevention proposal

1. Classify manifests and prefer the master presentation. For movie/episode
   requests, reject audio-only candidates and missing/unsupported video. Retain
   correct audio-group relationships instead of racing network responses.
2. Add bounded media preflight: inspect a representative segment with ffprobe,
   require a video stream with valid dimensions and a supported codec/profile/
   pixel format, and test local frame decoding. Inspect the *relayed* output as
   well as upstream input. Local decoding is not proof of the Roku display.
3. Prefer a compatible alternative provider before starting playback. If there
   is no supported source, fail with a specific reason. Do not silently stream
   audio only. Transcoding, if added, must be an explicit resource-bounded path,
   not an assumption that remuxing converts codecs.
4. Expose separate evidence fields for source validation, Roku player activity,
   and picture verification. Do not manufacture a `video_verified` claim from an
   advancing playback clock. A user-reported black picture should permit a
   deliberate retry with the failed candidate excluded.
5. Log bounded, sanitized diagnostic records: title/episode, provider, candidate
   class, codecs, pixel format, dimensions, selected rendition, stage durations,
   sanitized error codes and limited FFmpeg failure summaries. Never log session
   tokens, signed source URLs, browser cookies, or auth headers.
6. Mark source adapter support explicitly. Unsupported layouts should return a
   clear capability error or use the separately exposed constrained browser
   route. Preserve timeout stage and selector category in private diagnostics.
7. Add regression coverage for audio-only HLS, audio-before-master response order,
   split audio/video, missing resolution, unsupported video formats, and
   player-progress-without-picture evidence. Keep network policy protections.
8. Before a runtime fix is called complete, use an authorized TV acceptance run
   on this actual FHD Roku: visible video and audio, correct episode, pause/resume,
   and sustained playback. A package build, unit suite or first-segment fetch is
   not that acceptance result.

## PR acceptance review

Roomcast's existing `docs/acceptance.md` records a successful H.264/AAC test on a
40-inch Roku Select Series FHD TV, via a temporary Mac network forward. It
explicitly does not promise universal provider compatibility or a full episode.
Roomcast PR #3 and Nix PR #577 both left direct deployed TV-to-Spark playback as
an outstanding acceptance step. Their passing unit/build checks were not proof
that an arbitrary Silo rendition would be visible. The prevention work belongs
primarily in Roomcast; Nix should then pin the tested fix and preserve a clear
separation between build, deployment, and actual TV acceptance.

Roku's [streaming specifications](https://developer.roku.com/dev/docs/media)
distinguish container, codec and device-specific decoding support. Resolution
alone is not a compatibility check; stream copy changes packaging, not the codec.
