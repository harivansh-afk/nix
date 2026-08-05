# Frozen design: ix morning brief

Hari approved the mobile HTML version on 2026-08-05. Treat `templates/brief.html` as a frozen visual artifact: daily runs populate content slots and never redesign it.

## Posture

One clean phone scroll, not a dashboard, card carousel, multi-page report, or miniature magazine. The brief should be understandable in roughly a minute.

## Invariants

- Warm paper, near-black type, one oxide accent, and hairline separators.
- IBM Plex Sans when installed, with system sans fallbacks. No remote fonts, images, scripts, analytics, or network requests.
- Fluid type with a 44rem maximum reading width.
- One headline and framing paragraph, one compact activity strip, at most three landed workstreams, then at most four open loops.
- Body text remains at least 1rem on mobile. Metadata can be smaller because it never carries the substantive claim.
- Outcome-first grouping. PR references are provenance, not the layout's primary content.
- The output is a single self-contained `.html` attachment that opens locally on the phone.

## Why this replaced the PDF design

The earlier PDF spread one workstream per page and made a morning skim feel like homework. Compressing harder inside a fixed page made the type and hierarchy worse. HTML preserves readable type, gives the content natural vertical rhythm, and avoids arbitrary pagination while remaining a single private file.

## Change control

Any visual edit must be rendered at a 390px viewport against `fixtures/2026-08-05.json` and inspected for clipping, hierarchy, and full-content visibility. Content cap changes require matching renderer validation and test updates. Daily agents may not edit the template.
