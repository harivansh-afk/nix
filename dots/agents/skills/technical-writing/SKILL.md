---
name: technical-writing
description: Draft or revise technical papers and explanations in Hari's style by reasoning about evidence, reader knowledge and headings, then using Echo to turn an ordered brief into prose.
---

# Technical writing

Start with Hari's three questions:

1. What information am I presenting, and does it need more content?
2. What can I assume the reader already knows?
3. How best can I explain the concept given those assumptions?

Read the requested section and its neighbors before drafting. Recover the
relevant decisions and feedback from the conversation, not just the latest
outline. Read
[author references](references/author.md) for the writing samples and their
provenance. Use samples to learn explanation order and sentence construction;
use current evidence to decide what is true.

## Prepare the brief

Build the context handoff described in [the brief format](references/brief.md).
Include the accepted argument, audience assumptions, actual preceding prose,
and the section's destination. Identify what the reader knows on entry and
the missing connection this section supplies. Relevant prior feedback should
change this handoff, rather than merely accompany it as another transcript.

Separate supported reader-facing facts from instructions to the writer. Keep
units, quantifiers, conditions and uncertainty attached to each fact. Include
a concrete instance when it makes a mechanism easier to understand, even if
the section needs no numerical results. A block size can explain a mechanism
without being a result. Distinguish measurements, estimates and proposed work.

Arrange facts by their dependencies, not into one paragraph per bullet.
Give Echo room to combine or reorder points while preserving those
dependencies. Use a constraint/mechanism/consequence sequence where it fits;
let a methods section follow selection, procedure and interpretation. Remove
an isolated concept if the rest of the explanation never uses it, or move it
to the section that does.

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
the labeled blocks from the brief format and the three writing questions
above. Select a short, connected passage from the author samples so Echo sees
how one sentence makes the next necessary. Mark it as style-only and mark
preceding prose as already read by the reader. Historical drafts with stale
claims should contribute selected style excerpts, not an entire competing
version of the paper.

Ask for only the requested prose, using the chosen headings. Give a length
budget suited to the information and say whether tables count toward it.
Keep internal exclusions and workflow notes in the writer-only block. These
labels guide the model; they are not an API-enforced separation of channels.

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

Read across paragraph boundaries: does the next paragraph use what the reader
just learned, or start an unrelated miniature tutorial? Inspect paragraph
endings separately. Keep a concrete consequence, needed qualification or
transition; cut an abstract restatement that adds no information. Keep causal
chains intact when one sentence explains them clearly. Vary sentence length
with the thought, not to meet a rhythm score or a quota for words such as
"we" or "so".

Check for writer-only notes appearing as prose, definitions repeated from
earlier sections, unexplained labels inherited from the brief, and repeated
verbs that obscure distinct actions. Compare every qualifier to its source:
"one selected task per repository" does not mean a repository contains only
one task. Check actual length against the budget before accepting the output.

Reconsider the headings after the prose exists. Merge fragments of one
explanation; retain boundaries that help readers locate substantive content.
Make local edits directly. If the argument or structure needs substantial
repair, revise the handoff and make at most one corrective request for that
pass. Review that response too; if it still needs substantive rewriting,
finish the edits directly and describe Echo's contribution accurately.

Apply only the requested changes. Compare the final text with the original,
verify preserved content and document unresolved evidence separately from
finished prose. Completion means the requested passage is updated, its
claims survive review, and the heading structure serves the reader.
