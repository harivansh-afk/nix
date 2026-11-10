---
name: maintainable-code
description: Guidelines and a complexity check for writing maintainable code. Use when writing, refactoring or reviewing functions in any language.
---

1. A fixed set of values gets an enum or literal union instead of a string.
   bad:  if (piece.kind == "n")
   good: if (piece.kind == Kind.Knight)

2. Branch on a closed type with an exhaustive match.
   bad:  if (s == Open) return 1; else if (s == Done) return 2; else return 0;
   good: switch (s) { case Open: return 1; case Done: return 2; default: assertNever(s) }

3. Handle bad and empty cases first with early returns; keep the main path flat.
   bad:  if (paid) { if (inStock) { if (express) { ... } } }
   good: if (!paid || !inStock) return null; return express ? fast(item) : slow(item);

4. A branch chain mapping keys to values is a lookup table with a default.
   bad:  if (m == "jan") d = 31; else if (m == "feb") d = 28; ...
   good: d = DAYS[m] ?? 0

5. Repeated near-identical blocks become a list of data processed once.
   bad:  if (a) out.push("A"); if (b) out.push("B"); if (c) out.push("C");
   good: out = [[a, "A"], [b, "B"], [c, "C"]].filter(([on]) => on).map(([, l]) => l)

6. Nested loops that collect results become flatMap, filter, map.
   bad:  for (p of pieces) for (m of movesOf(p)) if (safe(m)) out.push(m)
   good: out = pieces.flatMap(movesOf).filter(safe)

7. Near-duplicate functions become one helper that takes the differing value.
   bad:  bishopMoves(sq), rookMoves(sq) with copied loops
   good: rayMoves(sq, DIAGONALS), rayMoves(sq, STRAIGHTS)

8. One job per function. Split along real seams, never just to lower a score.
   bad:  parseAndValidateAndSave(input)
   good: save(validate(parse(input)))

9. Model alternatives as a tagged union, not optional fields valid only in some combinations.
   bad:  { status: string, result?: Data, error?: string }
   good: { kind: "ok", result: Data } | { kind: "err", error: Error }

10. Name any literal whose meaning isn't obvious or that appears twice.
   bad:  if (retries > 3) sleep(86400)
   good: if (retries > MAX_RETRIES) sleep(ONE_DAY_SECONDS)

Then measure the files you touched:

uvx lizard -Ecognitive -ENS -s cognitive_complexity <files>

Fix any function you wrote over cognitive complexity 15, cyclomatic 10 or nesting 3, or give a reason it stays.
