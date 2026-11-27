---
name: technical-writing
description: Draft or revise technical papers and explanations in Hari's style by reasoning about evidence, reader knowledge and headings, then using Echo to turn an ordered brief into prose.
---

# Technical writing

Start with Hari's three questions:

1. What information am I presenting, and does it need more content?
2. What can I assume the reader already knows?
3. How best can I explain the concept given those assumptions?

Read the requested section and its neighbors before drafting. Read
[author references](references/author.md) for the writing samples and their
provenance. Use samples to learn explanation order and sentence construction;
use current evidence to decide what is true.

## Prepare the brief

Write points for Echo that specify:

- The section's purpose and what the reader should understand afterward.
- The audience's assumed knowledge, what earlier sections already explained,
  and the project-specific concepts that need explanation here.
- The supported claims in explanation order, with evidence pointers,
  qualifications and unresolved gaps. Distinguish measured results from
  estimates, interpretations and proposed work.
- Each paragraph's job and how it follows from the previous paragraph.
  Introduce a mechanism when the reader has enough context to need it.
- What belongs elsewhere, including implementation detail, results or
  definitions that would interrupt this section.

Resolve factual uncertainty from the source material before handing it to
Echo. Keep genuinely missing evidence explicit in the brief. Echo supplies
sentences, not research findings or citations.

## Decide the headings

Judge headings against the actual explanation, including adjacent sections.
For each proposed boundary, identify the new reader question or subject and
whether readers will need to find it independently. Use a paragraph break
when the thought simply continues. Keep subsections when several paragraphs
develop a distinct problem, method or result that merits navigation.

Choose a short label that names the content at that boundary. Read the
headings alone: they should reveal the paper's subjects and progression,
with siblings at comparable levels. Then read across each boundary: a
heading must not substitute for a missing logical connection. Conventional
labels such as Background or Methods are useful when they accurately set
expectations. Prefer specificity over decorative phrasing or a forced
pattern shared by every heading.

Record the chosen headings and the reason for each in the brief. For a short
continuous explanation, one section heading can be enough. A section title
must promise only what the section delivers; the paper title must reflect
the central supported contribution. Preserve an approved title unless the
user requests reconsideration.

## Draft with Echo

Read [the Echo workflow](references/echo.md). Assemble a prompt containing
the brief, the relevant surrounding text and selected author samples in
separate, labeled blocks. Include the three writing questions above. Ask for
only the requested prose, using the chosen headings and preserving the
brief's qualifications. Explicitly mark older drafts as style references
whose claims may be superseded.

Save the prompt and returned draft in the project's ignored artifact area.
Send only the material needed for the authorized writing task. Use Echo to
generate the prose before editing the manuscript. If the service fails,
report that fact and preserve the brief; identify any directly written
fallback as such.

## Review and apply

Read the output against the brief and neighboring sections. Check every
claim, number and citation against its source. Preserve uncertainty and
scope through edits. Remove sentences that merely announce a topic, repeat
known material or praise the work. Explain an unfamiliar term at its first
necessary use; keep ordinary technical vocabulary when the audience knows it.

Read each sentence as a continuation of the preceding one. Keep concrete
subjects, explicit causal relationships and enough detail to understand the
mechanism. Match the samples' reasoning rather than copying phrases,
sentence lengths or informal asides into an unsuitable genre.

Reconsider the headings after the prose exists. Merge fragments of one
explanation; retain boundaries that help readers locate substantive content.
Make local edits directly. If the argument or structure needs substantial
repair, revise the brief and make a bounded follow-up request to Echo.

Apply only the requested changes. Compare the final text with the original,
verify preserved content and document unresolved evidence separately from
finished prose. Completion means the requested passage is updated, its
claims survive review, and the heading structure serves the reader.
