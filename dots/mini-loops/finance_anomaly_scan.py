#!/usr/bin/env python3
"""finance_anomaly_scan.py - print deterministic spending anomaly CANDIDATES.

The gather step for the finance-anomaly-watch mini-loop. Reads the locally-ingested
finance notes (frontmatter: date, merchant, amount, currency, account, source) and
computes anomaly candidates in PYTHON (no LLM here - the gate decides which are
worth surfacing). Local-only and sensitive: this only prints text to stdout for the
loop; nothing here touches the network.

We only care about REAL spending anomalies, so the detector ignores income,
refunds, transfers, and fee noise up front and looks for three things:

  - SUBSCRIPTION : a merchant billing on a recurring cadence (roughly weekly or
    monthly) at a STABLE amount. This is the core value - surfacing recurring
    subscriptions, especially forgotten/random ones. High-frequency variable spend
    (food delivery, rideshare, coffee runs) is explicitly NOT a subscription and is
    filtered out by the amount-stability + cadence checks.
  - LARGE CHARGE : a single debit that is a large multiple of that merchant's
    median AND a meaningful absolute amount (catches a one-off blowout).
  - DUPLICATE    : the same merchant charging the same amount on the SAME day more
    than once (genuine double-billing - NOT the same amount across different days).

Each subscription whose latest amount rose materially over its prior amounts also
carries a "(price up ...)" note - we never flag price changes for non-subscription
spend.

Already-flagged anomalies are persisted in
$MINI_LOOPS_DIR/state/finance-anomaly-watch.json (keyed by a stable signature) so
each is reported once. UNLIKE dep-release-watch, finance SURFACES on the first run
(empty state) so Hari sees his existing subscriptions immediately; every candidate
is then recorded and deduped so it is reported once going forward. On any error it
prints nothing and exits 0 (loop -> SKIP).

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

# Subscription cadence/stability tunables.
MIN_RECUR = 2            # need at least this many charges to call a merchant recurring
WEEKLY_LO, WEEKLY_HI = 5.0, 10.0    # median gap (days) that counts as ~weekly
MONTHLY_LO, MONTHLY_HI = 24.0, 38.0  # median gap (days) that counts as ~monthly
GAP_SPREAD_MAX = 0.6     # gaps must be fairly regular: stdev/mean(gap) <= this
AMT_SPREAD_MAX = 0.18    # amounts must be stable: stdev/mean(amount) <= this
SUB_MIN_AMOUNT = 1.0     # ignore sub-dollar "subscriptions" (transit taps etc.)
RECENT_SUB_DAYS = 60     # only surface subs charged within this window (else stale)

# Large-outlier tunables.
LARGE_MULT = 4.0         # large charge = > this x the merchant median
LARGE_MIN_ABS = 75.0     # ...and at least this many dollars (skip trivial blips)

# Same-day duplicate billing. Small-ticket merchants (transit taps, scooter
# rides, coffee) legitimately repeat on a day, so only a non-trivial repeated
# amount looks like a double-charge worth flagging.
DUP_MIN_AMOUNT = 15.0

# Price-rise note on an existing subscription.
HIKE_FRAC = 0.15         # latest amount > this fraction above prior median -> note

# Merchant phrases that mean "not real discretionary spend": income, refunds,
# transfers between Hari's own accounts/people, and bank fees. Matched on the
# normalized (lowercased) merchant name; any debit hitting one is dropped.
EXCLUDE_SUBSTR = (
    "zelle",
    "wire",
    "venmo",
    "transfer",
    "indexable inc",
    "refund",
    "transaction fee",
    "wire transfer fee",
    "atm",
    "cash app",
    "cashapp",
    "interest",
    "payment thank you",
    "online payment",
    "bill pay",
)


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
    """Return the SIGNED amount (negative = spend), or None if unparseable."""
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def _norm_merchant(name: str) -> str:
    return re.sub(r"\s+", " ", (name or "").strip()).lower()


def _is_excluded(key: str) -> bool:
    return any(sub in key for sub in EXCLUDE_SUBSTR)


def _median(vals: list[float]) -> float:
    s = sorted(vals)
    n = len(s)
    if n == 0:
        return 0.0
    mid = n // 2
    if n % 2:
        return s[mid]
    return (s[mid - 1] + s[mid]) / 2.0


def _mean(vals: list[float]) -> float:
    return sum(vals) / len(vals) if vals else 0.0


def _cv(vals: list[float]) -> float:
    """Coefficient of variation (stdev/mean); 0 for <2 values or zero mean."""
    if len(vals) < 2:
        return 0.0
    mu = _mean(vals)
    if mu == 0:
        return 0.0
    var = sum((v - mu) ** 2 for v in vals) / len(vals)
    return (var ** 0.5) / abs(mu)


def _cadence_label(median_gap: float) -> str | None:
    """Map a median inter-charge gap (days) to a subscription cadence, or None."""
    if WEEKLY_LO <= median_gap <= WEEKLY_HI:
        return "weekly"
    if MONTHLY_LO <= median_gap <= MONTHLY_HI:
        return "monthly"
    return None


def _load_charges() -> list[dict]:
    """Read every finance note (transactions + charges); return parsed records.

    Records keep the SIGNED amount; downstream logic decides what counts as spend.
    Records whose merchant looks like income/transfer/fee noise are dropped here so
    nothing in that bucket can become an anomaly.
    """
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
            key = _norm_merchant(merchant)
            if _is_excluded(key):
                continue  # income / transfer / refund / fee - never an anomaly
            records.append(
                {
                    "merchant": merchant.strip(),
                    "key": key,
                    "date": dt,
                    "amount": amt,  # signed; may be None (some email charges lack it)
                }
            )
    return records


def _debits(recs: list[dict]) -> list[dict]:
    """Charges that are actual spend: amount present and negative (outflow)."""
    return [r for r in recs if r["amount"] is not None and r["amount"] < 0]


def _subscription_candidate(
    name: str, debs: list[dict], today: date
) -> tuple[str, str] | None:
    """If these debits look like a recurring subscription, return (sig, line)."""
    debs = sorted(debs, key=lambda r: r["date"])
    if len(debs) < MIN_RECUR:
        return None
    amts = [abs(r["amount"]) for r in debs]
    if _median(amts) < SUB_MIN_AMOUNT:
        return None
    dates = [r["date"] for r in debs]
    if dates[-1] < today - timedelta(days=RECENT_SUB_DAYS):
        return None  # gone quiet - not a live subscription worth surfacing
    gaps = [(dates[i + 1] - dates[i]).days for i in range(len(dates) - 1)]
    gaps = [g for g in gaps if g > 0]  # drop same-day pairs from cadence math
    if not gaps:
        return None
    cadence = _cadence_label(_median(gaps))
    if cadence is None:
        return None  # not weekly/monthly -> bursty discretionary spend, not a sub
    # Two charges a week apart is too weak to call a subscription (it is usually
    # just food/coffee twice) - require >=3 for the weekly band. Monthly subs
    # legitimately show only 2 charges across two billing cycles.
    if cadence == "weekly" and len(debs) < 3:
        return None
    # Regular spacing and stable amount distinguish a subscription from a frequent
    # merchant (rideshare/food) that happens to fall in the cadence band.
    if _cv(gaps) > GAP_SPREAD_MAX or _cv(amts) > AMT_SPREAD_MAX:
        return None
    typical = _median(amts)
    sig = f"sub:{debs[-1]['key']}:{cadence}"
    note = ""
    if len(amts) >= 2:
        prior = amts[:-1]
        pm = _median(prior)
        if pm > 0 and amts[-1] > pm * (1.0 + HIKE_FRAC):
            note = f" (price up: {pm:.2f} -> {amts[-1]:.2f})"
    line = (
        f"SUBSCRIPTION: {name} ~{typical:.2f}/charge every ~{_median(gaps):.0f}d "
        f"({len(debs)} charges, last {dates[-1].isoformat()}){note}"
    )
    return sig, line


def _candidates(records: list[dict], today: date) -> list[tuple[str, str]]:
    """Compute anomaly candidates. Returns [(signature, text_line)]."""
    by_merchant: dict[str, list[dict]] = {}
    for r in records:
        by_merchant.setdefault(r["key"], []).append(r)

    out: list[tuple[str, str]] = []

    for key, recs in by_merchant.items():
        debs = _debits(recs)
        if not debs:
            continue
        name = sorted(debs, key=lambda r: r["date"])[-1]["merchant"]

        # (a) SUBSCRIPTION: recurring, regular, stable-amount spend.
        sub = _subscription_candidate(name, debs, today)
        if sub is not None:
            out.append(sub)

        # (b) LARGE CHARGE: a single debit that dwarfs the merchant's usual AND is
        #     a meaningful absolute amount. Needs a few prior charges for a median.
        amounts = [abs(r["amount"]) for r in debs]
        if len(amounts) >= 3:
            med = _median(amounts)
            if med > 0:
                for r in debs:
                    a = abs(r["amount"])
                    if a >= LARGE_MIN_ABS and a > LARGE_MULT * med:
                        sig = f"large:{key}:{r['date'].isoformat()}:{a:.2f}"
                        out.append(
                            (
                                sig,
                                f"LARGE CHARGE: {name} charged {a:.2f} on "
                                f"{r['date'].isoformat()}, ~{a / med:.1f}x its usual "
                                f"{med:.2f}.",
                            )
                        )

    # (c) DUPLICATE: same merchant + same amount on the SAME day, more than once.
    seen: dict[tuple, int] = {}
    for r in _debits(records):
        amt = abs(r["amount"])
        if amt < DUP_MIN_AMOUNT:
            continue
        dk = (r["key"], r["date"].isoformat(), round(amt, 2))
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
    flagged = set(state.get("flagged", []))

    candidates = _candidates(records, today)
    new_lines: list[str] = []
    for sig, line in candidates:
        if sig in flagged:
            continue  # already reported once
        flagged.add(sig)
        new_lines.append(line)

    state["flagged"] = sorted(flagged)
    _save_state(state)

    # Unlike dep-release-watch, finance surfaces on the first run too, so the
    # existing subscriptions/anomalies are seen immediately. Each is recorded
    # above and deduped on subsequent runs.
    for line in new_lines:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
