#!/usr/bin/env python3
"""finance_anomaly_scan.py - print deterministic spending anomaly CANDIDATES.

The gather step for the finance-anomaly-watch mini-loop. Reads the locally-ingested
finance notes (frontmatter: date, merchant, amount, currency, account, source) and
computes anomaly candidates in PYTHON (no LLM here - the gate decides which are
worth surfacing). Local-only and sensitive: this only prints text to stdout for the
loop; nothing here touches the network.

Candidate kinds (each emitted as a text line the gate can judge):
  - NEW SUBSCRIPTION : a merchant that recurs (>= MIN_RECUR charges, roughly
    regular spacing) whose FIRST charge is within the last NEW_SUB_DAYS days.
  - LARGE CHARGE     : a single charge > LARGE_MULT x that merchant's median.
  - DUPLICATE        : same merchant + same amount on the same day.
  - PRICE HIKE       : a recurring merchant whose latest amount is > HIKE_FRAC
    above the median of its prior amounts.

Already-flagged anomalies are persisted in
$MINI_LOOPS_DIR/state/finance-anomaly-watch.json (keyed by a stable signature) so
each is reported once. On the FIRST run (empty state) it records every current
candidate as flagged WITHOUT emitting and prints a baseline note to stderr - the
finance data is bulk-ingested, so a cold start would otherwise flag the entire
back-catalogue at once. After the baseline only genuinely new anomalies surface.
On any error it prints nothing and exits 0 (loop -> SKIP).

Env:
  MINI_LOOPS_DIR     state root (default /var/lib/mini-loops)
  FINANCE_KB_DIR     finance notes root (default /var/lib/kb/staging/finance)
"""

import json
import os
import re
import sys
from datetime import date, datetime, timedelta

STATE_DIR = os.path.join(
    os.environ.get("MINI_LOOPS_DIR", "/var/lib/mini-loops"), "state"
)
STATE_FILE = os.path.join(STATE_DIR, "finance-anomaly-watch.json")
FINANCE_DIR = os.environ.get("FINANCE_KB_DIR", "/var/lib/kb/staging/finance")

# Tunables (kept conservative - the gate adds a second skeptic pass on top).
MIN_RECUR = 2          # a merchant must charge at least this often to "recur"
NEW_SUB_DAYS = 30      # "new" subscription = first charge within this window
LARGE_MULT = 3.0       # large charge = > this x the merchant median
HIKE_FRAC = 0.20       # price hike = latest amount > this fraction above prior median
DUP_MIN_AMOUNT = 1.0   # ignore tiny same-day duplicates (rounding noise)


def _load_state() -> dict:
    try:
        with open(STATE_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_state(state: dict) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as fh:
            json.dump(state, fh, indent=2)
    except Exception as exc:
        print(f"finance: state write failed: {exc}", file=sys.stderr)


_FM = re.compile(r"^---\s*\n(.*?)\n---", re.DOTALL)


def _parse_frontmatter(text: str) -> dict:
    m = _FM.search(text)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        out[key.strip()] = val.strip()
    return out


def _parse_date(raw: str) -> date | None:
    raw = (raw or "").strip()
    if not raw:
        return None
    # Plain ISO (transactions): 2026-06-24
    try:
        return datetime.strptime(raw[:10], "%Y-%m-%d").date()
    except ValueError:
        pass
    # RFC-2822-ish (email charges): Mon, 22 Jun 2026 22:05:52 +0000 (UTC)
    m = re.search(r"(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})", raw)
    if m:
        try:
            return datetime.strptime(
                f"{m.group(1)} {m.group(2)} {m.group(3)}", "%d %b %Y"
            ).date()
        except ValueError:
            return None
    return None


def _parse_amount(raw: str) -> float | None:
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        # Spend is negative in the source; anomalies are about magnitude.
        return abs(float(raw))
    except ValueError:
        return None


def _norm_merchant(name: str) -> str:
    return re.sub(r"\s+", " ", (name or "").strip()).lower()


def _median(vals: list[float]) -> float:
    s = sorted(vals)
    n = len(s)
    if n == 0:
        return 0.0
    mid = n // 2
    if n % 2:
        return s[mid]
    return (s[mid - 1] + s[mid]) / 2.0


def _load_charges() -> list[dict]:
    """Read every finance note (transactions + charges); return parsed records."""
    records: list[dict] = []
    for sub in ("transactions", "charges"):
        d = os.path.join(FINANCE_DIR, sub)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".md"):
                continue
            try:
                with open(os.path.join(d, fn), encoding="utf-8") as fh:
                    fm = _parse_frontmatter(fh.read())
            except Exception:
                continue
            merchant = fm.get("merchant", "")
            dt = _parse_date(fm.get("date", ""))
            amt = _parse_amount(fm.get("amount", ""))
            if not merchant or dt is None:
                continue
            records.append(
                {
                    "merchant": merchant.strip(),
                    "key": _norm_merchant(merchant),
                    "date": dt,
                    "amount": amt,  # may be None (some email charges lack amounts)
                }
            )
    return records


def _candidates(records: list[dict], today: date) -> list[tuple[str, str]]:
    """Compute anomaly candidates. Returns [(signature, text_line)]."""
    by_merchant: dict[str, list[dict]] = {}
    for r in records:
        by_merchant.setdefault(r["key"], []).append(r)

    out: list[tuple[str, str]] = []
    cutoff = today - timedelta(days=NEW_SUB_DAYS)

    for key, recs in by_merchant.items():
        recs = sorted(recs, key=lambda r: r["date"])
        name = recs[-1]["merchant"]
        amounts = [r["amount"] for r in recs if r["amount"] is not None]
        n = len(recs)

        # (a) NEW SUBSCRIPTION: recurs and first charge is within the window.
        first = recs[0]["date"]
        if n >= MIN_RECUR and first >= cutoff:
            sig = f"newsub:{key}"
            out.append(
                (
                    sig,
                    f"NEW SUBSCRIPTION: {name} - {n} charges since {first.isoformat()} "
                    f"(first seen within {NEW_SUB_DAYS}d), looks like a new recurring "
                    "merchant.",
                )
            )

        # (b) LARGE CHARGE: a charge > LARGE_MULT x the merchant median.
        if len(amounts) >= 3:
            med = _median(amounts)
            if med > 0:
                for r in recs:
                    a = r["amount"]
                    if a is not None and a > LARGE_MULT * med:
                        sig = f"large:{key}:{r['date'].isoformat()}:{a:.2f}"
                        out.append(
                            (
                                sig,
                                f"LARGE CHARGE: {name} charged {a:.2f} on "
                                f"{r['date'].isoformat()}, ~{a / med:.1f}x its usual "
                                f"{med:.2f}.",
                            )
                        )

        # (d) PRICE HIKE: latest amount > HIKE_FRAC above prior median.
        if n >= MIN_RECUR and len(amounts) >= 2:
            prior = amounts[:-1]
            latest = amounts[-1]
            pm = _median(prior)
            if pm > 0 and latest > pm * (1.0 + HIKE_FRAC):
                sig = f"hike:{key}:{latest:.2f}"
                out.append(
                    (
                        sig,
                        f"PRICE HIKE: {name} latest charge {latest:.2f} is "
                        f"{(latest / pm - 1) * 100:.0f}% above its prior usual "
                        f"{pm:.2f}.",
                    )
                )

    # (c) DUPLICATE: same merchant + amount + day, more than once.
    seen: dict[tuple, int] = {}
    for r in records:
        if r["amount"] is None or r["amount"] < DUP_MIN_AMOUNT:
            continue
        dk = (r["key"], r["date"].isoformat(), round(r["amount"], 2))
        seen[dk] = seen.get(dk, 0) + 1
    for (key, day, amt), count in seen.items():
        if count >= 2:
            name = next((r["merchant"] for r in records if r["key"] == key), key)
            sig = f"dup:{key}:{day}:{amt:.2f}"
            out.append(
                (
                    sig,
                    f"DUPLICATE CHARGE: {name} charged {amt:.2f} {count} times on "
                    f"{day} (possible double-billing).",
                )
            )

    return out


def main() -> int:
    try:
        records = _load_charges()
    except Exception as exc:
        print(f"finance: load failed: {exc}", file=sys.stderr)
        return 0
    if not records:
        return 0

    today = max(r["date"] for r in records)
    state = _load_state()
    first_run = "flagged" not in state
    flagged = set(state.get("flagged", []))

    candidates = _candidates(records, today)
    new_lines: list[str] = []
    for sig, line in candidates:
        if sig in flagged:
            continue
        flagged.add(sig)
        if first_run:
            continue  # baseline only; do not surface the back-catalogue
        new_lines.append(line)

    state["flagged"] = sorted(flagged)
    _save_state(state)

    if first_run:
        print(
            f"finance: baseline recorded for {len(flagged)} candidates "
            "(none surfaced on first run)",
            file=sys.stderr,
        )
        return 0

    for line in new_lines:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
