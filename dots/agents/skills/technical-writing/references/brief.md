# Context for the writing model

Use these labeled blocks to prepare a section draft. Keep the handoff smaller
than the source material: extract decisions and evidence, and include actual
prose where its continuity matters. The blocks are input organization, not
headings to reproduce in the document.

## Task and accepted decisions

Name the exact passage to produce, its purpose, audience, chosen headings and
length budget. Include prior decisions that affect this passage: the central
claim, scope, terminology and what the user has rejected. State what this
section must add and what the next section will establish. Preserve these
decisions when a generation attempt is retried.

## Already read by the reader

Supply the actual preceding passage and a compact list of concepts it has
established. For a long document, summarize distant sections and include the
immediate preceding paragraphs verbatim. Add the following passage when
revising a middle section. This text is continuity context, not material to
paraphrase into the requested passage. Mark whether adjacent text is finished
prose or only a plan.

## Facts available to the reader

List the facts needed here with their source pointers, units and qualifiers.
Explain dependencies and provide one concrete example if it removes an
otherwise abstract step. Label hypothetical examples as illustrative. Supply
tables exactly when the values have already been checked. These are the
facts Echo may express, not a demand to turn every bullet into a paragraph.

Distinguish reader-relevant limitations from internal reminders. For example,
that commands ran in containers matters to interpreting a VM experiment;
the writer's reminder to avoid overstating a baseline is not itself a finding.
Resolve factual uncertainty before drafting or keep the remaining gap visible
in the agent's working notes, without inventing a value to fill it.

## Author passage: style only

Include a connected excerpt whose form fits the task. Explain what it
demonstrates: the assumed knowledge, a causal connection, the mechanism's
consequence or a useful heading boundary. Prefer a few connected paragraphs
over a collection of punchy sentences. The excerpt's facts belong to its
original document and are not evidence for this one.

## Writer-only instructions

Put exclusions, review cautions and prior generation failures here. They
govern the draft but must not appear as apologies, process reports or
announcements of future evaluation. Keep them short and targeted. Ask for the
requested prose only, with no explanation of how it was written.

In a retry, retain the accepted decisions, preceding context and verified
facts. Correct the failed relationship or qualifier and remove distracting
material. A longer list of prohibitions does not replace missing context.
