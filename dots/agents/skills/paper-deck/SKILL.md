---
name: paper-deck
description: Write and build a talk deck (slides, presentation, checkpoint, meeting update; "make slides", "rebuild the deck") as paper notes with hidden talking points.
---

# Paper deck

A deck for a technical meeting, written the way notes land on paper: one thought
per slide, said plainly to a peer who follows the vibe, with the reasoning behind
each decision. Excalidraw-style diagrams under the text. Talking points stay
hidden until asked for. Everything else on screen is gone.

## Process

1. Read the actual state of the work: checklists, validation logs, the spec,
   reviews, commits. Every claim on a slide traces to one of these.
2. Draft the deck as data: an array of slides, each with `lines`, an optional
   `figure`, and `notes`. Prose drafts drift into headings; data keeps the form.
3. Cut every slide that carries no decision, no result and no diagram.
4. Render, then screenshot at least one text slide and one diagram slide and
   look at them. Done means both screenshots match the layout rules below.

## Writing

One thought per slide. Two to five lines, each a sentence you could say aloud.
The first line is the thought; the rest support it. First person, present tense,
plain register: "I moved the cache to disk because memory was the ceiling."

Technical terms are used on the slide and defined in the notes as a predicted
question. Numbers come from a measurement or a source, or carry the word
"unmeasured". Sources live in the notes.

An experiment slide says three things: what the result proves, what it does not
prove, and what it changes about the decision.

A decision already made is stated with its reason. A decision still open is a
question to the audience, followed by the presenter's own take.

The slide holds only the lines and the figure. Titles, section labels, kickers,
bullet glyphs and footers are all forms of the same thing, a summary layered on
the thought; the thought already is the summary.

## Notes

Hidden by default. Three to six per slide. Some are what to say; the rest are
predicted questions in the form `Q: … A: …` with a two-sentence answer. Limits
and caveats belong here: sample size, unmeasured figures, source-review-only.

## Diagrams

Box-and-arrow, Excalidraw-like. At most eight boxes. One accent colour for the
thing the slide is about, muted for context, dashed for not-yet-built or a
boundary. Comparisons run left to right: today on the left, proposed on the
right. Labels are two or three words.

A bar chart appears only for a measured number. Tables and decorative charts
belong in the notes or nowhere.

## Layout and chrome

Full-screen slide, content vertically centred, one column of text with the
diagram under it. One visible control: a faded back link top-left. The rest of
the chrome (header bar, counter, prev/next buttons, eyebrow labels) does not
exist.

Keyboard: arrows, space, PageUp and PageDown move; Home and End jump; Escape
leaves; `?` toggles the notes. Hovering the bottom edge of the screen also
reveals the notes.

Without JavaScript the deck reads as a document with the notes visible. Print
gives one slide per page with its notes.

## Example slide

```js
{
  lines: [
    "I batch writes on the client because the server round trip is the ceiling.",
    "p50 latency drops from 42 ms to 9 ms on the replay set (n = 200).",
    "This proves batching helps the hot path; it says nothing about cold starts.",
    "Batching stays. Cold start is a separate experiment.",
  ],
  figure: "client-batch",
  notes: [
    "Say: the replay set is last week's real traffic, not synthetic.",
    "Q: What is the replay set? A: Two hundred requests captured from production and replayed against both builds. Same inputs, same order.",
    "Q: Why not batch on the server too? A: Server batching needs a queue we have not built. Client batching needed forty lines.",
    "Caveat: single machine, unmeasured under concurrent load.",
  ],
}
```
