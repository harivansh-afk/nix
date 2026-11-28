# Author references

Hari's writing process, supplied with the skill request on 27 November 2026:

> For technical writing i have to think about :
> 1. the information i am presenting and if it needs more content
> 2. what i can assume the user already knows
> 3. how best to explain the concept i am trying to get across given 2.

## Compiling BAML to Rust

Public source: https://hari.cafe/w/baml-rust/

The following excerpts were checked against the author's website source at
revision `2141772a4a357c46c62d256e446984bb54ba23fb`,
`src/routes/w/(post)/baml-rust/+page.svelte`. They are writing samples,
not evidence for a new document's technical claims.

> MIR is basic blocks connected by gotos, and Rust has no `goto`.
> We must make do with loops, ifs and breaks.

> The second thing Rust doesn't offer by default is pausing a function during execution. A function's locals live in its stack frame, which is popped on return, so compiled code can't hand control back to the VM mid-call and resume later.

> The usual workaround is compiling every function that may suspend into a state machine (Rust's `async` does this). Since suspension is transitive, this design spreads to ~69% of compiled functions and makes them ~1.3–1.8x slower than the interpreter itself.

> We solve this with stackful coroutines. Each VM owns a separate stack (a `fiber`) and compiled code runs on it, so suspending is just a context switch between two stacks on the same thread.

> A function pauses by calling `vm.suspend` with a request such as `Await(future)`. `suspend` pushes the callee-saved registers onto the fiber and switches the stack pointer back to the thread's stack, returning control to the VM.
> The VM handles the request the same way it would for the interpreter and schedules other tasks in the meantime.

> To resume, the VM switches the stack pointer back to the fiber and restores the registers. `suspend` then returns the request's result like an ordinary function call.

The reader is assumed to know functions and stacks. The explanation supplies
the missing connection between stack lifetime and suspension, then describes
what changes to support suspension. Concrete headings such as Control flow,
Pausing and Garbage collection mark different implementation problems.
The suspension mechanism also makes the resume paragraph understandable:
the reader now knows which stack and registers must be restored. Preserve
that dependency when selecting a passage for Echo. Sentence-length statistics
can reveal flat prose, but reproducing their values is not a writing goal.

## Handwritten research opening

Hari identified the original CAS abstract and introduction as handwritten.
When working in that research repository, retrieve them locally with:

```sh
git -C ~/Documents/Git/cas show 369672fc48501f5e5210464e2d05b68877e98a85:draft/paper.md
```

Select the opening before Background. Keep this private manuscript in the
task's local prompt artifacts, rather than copying it into the shared skill.
Some original claims were subsequently corrected: use this version for
style only and use the current evidence for factual content. If the checkout
is unavailable, use the public excerpts above and any samples supplied with
the task; do not claim to have read the handwritten opening.

Its useful pattern is to explain what a system shares, what constrains that
sharing, and the consequence for a particular disk or host before reporting
aggregate results. Learn that progression without importing the paper's
workload scope or findings into unrelated writing.
