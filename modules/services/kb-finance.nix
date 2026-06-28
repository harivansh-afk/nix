{ pkgs, ... }:
# kb-finance.nix - local-only personal-finance ingestion into the KB.
#
# Feeds ONE local-only finance namespace under /var/lib/kb/staging/finance/ so
# the agent has a centralized, linkable understanding of spend. Two sources, the
# SAME normalized entity shape (merchant, amount, date), so the off-hours Cognee
# graph (kb-graph.nix) can link a bank transaction to its receipt email by
# merchant + amount + date:
#
#   1. SimpleFIN Bridge (read-only access URL) -> finance/transactions/<id>.md
#   2. Charge / receipt emails, mined READ-ONLY from the already-staged gmail
#      markdown the gmail connector wrote -> finance/charges/<id>.md
#
# Privacy posture: this data is local-only and lives in its own namespace. It is
# never exfiltrated. The ~/Documents/Downloads/documents/finance-tax denylist
# STAYS (tax docs excluded) - this carve-out is ONLY for transaction + charge
# data the agent needs to reason about spend. See dots/hermes/TOOLS.md.
#
# Both connectors run as rathi (staging is rathi-owned) and are idempotent: the
# SimpleFIN note key is the stable transaction id; the charge note key is a
# content hash of (merchant, amount, date) so reruns over the same gmail message
# do not duplicate. Both no-op cleanly (log + exit 0) when their input is absent
# (no SimpleFIN token / no gmail staging yet), exactly like the gws connectors.
let
  user = "rathi";
  group = "users";
  stagingDir = "/var/lib/kb/staging";
  financeDir = "${stagingDir}/finance";
  gmailDir = "${stagingDir}/gmail";

  # Python env for the extractors: stdlib + requests (verified nixpkgs attr).
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.requests ]);

  # SimpleFIN connector: read SIMPLEFIN_ACCESS_URL from the sops secret; if
  # absent, log and exit 0. Otherwise GET <access_url>/accounts and normalize
  # each transaction into finance/transactions/<id>.md.
  simplefinScript = pkgs.writeText "kb-finance-simplefin.py" ''
    import json
    import os
    import sys
    import time
    from datetime import datetime, timezone

    import requests

    OUT = ${builtins.toJSON "${financeDir}/transactions"}
    SECRET = "/run/secrets/simplefin.env"


    def log(msg: str) -> None:
        print(f"kb-finance/simplefin: {msg}", flush=True)


    def access_url() -> str:
        # The secret is a KEY=value dotenv with SIMPLEFIN_ACCESS_URL=...
        # (the URL carries HTTP Basic credentials inline). Prefer the env var
        # if systemd already loaded the file; else parse the file directly.
        url = os.environ.get("SIMPLEFIN_ACCESS_URL", "").strip()
        if url:
            return url
        try:
            with open(SECRET, "r", encoding="utf-8") as handle:
                for raw in handle:
                    line = raw.strip()
                    if line.startswith("SIMPLEFIN_ACCESS_URL="):
                        return line.split("=", 1)[1].strip().strip('"').strip("'")
        except OSError:
            return ""
        return ""


    def iso(epoch) -> str:
        try:
            return datetime.fromtimestamp(int(epoch), tz=timezone.utc).strftime("%Y-%m-%d")
        except (TypeError, ValueError):
            return ""


    def write_note(txn: dict, account: dict) -> bool:
        txn_id = str(txn.get("id") or "").strip()
        if not txn_id:
            return False
        # Stable, filesystem-safe id for dedupe (the timer reruns hourly).
        safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in txn_id)
        path = os.path.join(OUT, f"{safe}.md")

        date = iso(txn.get("posted") or txn.get("transacted-at"))
        amount = str(txn.get("amount") or "").strip()
        # SimpleFIN has no merchant field; description/payee is the merchant.
        merchant = (txn.get("payee") or txn.get("description") or "").strip()
        description = (txn.get("description") or "").strip()
        currency = (account.get("currency") or "").strip()
        acct_name = (account.get("name") or "").strip()
        org = account.get("org") or {}
        org_name = (org.get("name") or org.get("domain") or "").strip() if isinstance(org, dict) else ""
        category = ""  # SimpleFIN does not categorize; left blank for the graph.

        # Frontmatter keeps the entity shape identical to charges/ notes so the
        # graph can link a transaction to its receipt email by these values.
        lines = [
            "---",
            f"date: {date}",
            f"merchant: {merchant}",
            f"amount: {amount}",
            f"currency: {currency}",
            f"account: {acct_name}",
            f"institution: {org_name}",
            f"category: {category}",
            "source: simplefin",
            f"id: {txn_id}",
            "---",
            "",
            f"# {merchant or '(transaction)'} - {amount} {currency}".rstrip(),
            "",
            f"- Date: {date}",
            f"- Merchant: {merchant}",
            f"- Amount: {amount} {currency}".rstrip(),
            f"- Account: {acct_name}",
            f"- Institution: {org_name}",
            "- Source: simplefin",
            "",
            description,
            "",
        ]
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines))
        return True


    def main() -> int:
        url = access_url()
        if not url:
            log("skipping: no SimpleFIN token")
            return 0

        os.makedirs(OUT, exist_ok=True)

        # Pull a rolling window so the timer stays light. 120 days of recent
        # transactions; start-date is inclusive Unix epoch.
        start = int(time.time()) - 120 * 24 * 3600
        endpoint = url.rstrip("/") + "/accounts"
        try:
            resp = requests.get(endpoint, params={"start-date": start}, timeout=60)
            resp.raise_for_status()
            data = resp.json()
        except requests.RequestException as exc:
            log(f"SimpleFIN API unreachable; skipping: {exc}")
            return 0
        except ValueError as exc:
            log(f"SimpleFIN returned non-JSON; skipping: {exc}")
            return 0

        for err in data.get("errors", []) or data.get("errlist", []):
            log(f"SimpleFIN warning: {err}")

        written = 0
        for account in data.get("accounts", []) or []:
            for txn in account.get("transactions", []) or []:
                if write_note(txn, account):
                    written += 1
        log(f"wrote {written} transaction note(s) to {OUT}")
        return 0


    sys.exit(main())
  '';

  # Charge-email extractor: scan the already-staged gmail markdown READ-ONLY,
  # identify expenditure / receipt / charge / order / payment messages, and emit
  # normalized finance notes with the SAME entity shape so the graph can link
  # them to SimpleFIN transactions. Does NOT re-fetch gmail.
  chargesScript = pkgs.writeText "kb-finance-charges.py" ''
    import hashlib
    import os
    import re
    import sys

    GMAIL = ${builtins.toJSON gmailDir}
    OUT = ${builtins.toJSON "${financeDir}/charges"}

    # Senders / subjects that mark a message as a charge or receipt. Kept broad
    # but specific enough to avoid pulling in newsletters: the words below are
    # transactional. Matched case-insensitively against subject + from.
    RECEIPT_PATTERNS = re.compile(
        r"\b("
        r"receipt|your order|order confirmation|payment received|payment of|"
        r"you (?:paid|sent)|charged|charge of|invoice|purchase|transaction|"
        r"subscription renewed|renewal|refund|has shipped|order #"
        r")\b",
        re.IGNORECASE,
    )
    # Senders that are almost always transactional.
    SENDER_PATTERNS = re.compile(
        r"(receipts?@|billing@|invoice|no-?reply@(?:.*?)(?:stripe|square|paypal|venmo|"
        r"amazon|apple|uber|lyft|doordash|instacart)|orders?@|payments?@)",
        re.IGNORECASE,
    )

    AMOUNT = re.compile(r"(?:[$£€]|USD|EUR|GBP)\s?([0-9][0-9,]*\.?[0-9]{0,2})", re.IGNORECASE)
    CURRENCY_SYMBOL = {"$": "USD", "£": "GBP", "€": "EUR"}


    def log(msg: str) -> None:
        print(f"kb-finance/charges: {msg}", flush=True)


    def parse_note(text: str) -> dict:
        # The gmail connector writes: "# <subject>", "- From: ...", "- Date: ...",
        # "- Source: gmail", then a blank line and the snippet.
        subject = ""
        frm = ""
        date = ""
        for line in text.splitlines():
            if not subject and line.startswith("# "):
                subject = line[2:].strip()
            elif line.startswith("- From:"):
                frm = line.split(":", 1)[1].strip()
            elif line.startswith("- Date:"):
                date = line.split(":", 1)[1].strip()
        return {"subject": subject, "from": frm, "date": date, "body": text}


    def is_charge(note: dict) -> bool:
        hay = f"{note['subject']} {note['from']}"
        return bool(RECEIPT_PATTERNS.search(hay) or SENDER_PATTERNS.search(note["from"]))


    def extract_amount(text: str) -> tuple[str, str]:
        match = AMOUNT.search(text)
        if not match:
            return "", ""
        amount = match.group(1).replace(",", "")
        sym = match.group(0)[0]
        currency = CURRENCY_SYMBOL.get(sym, "")
        if not currency:
            up = match.group(0).upper()
            for code in ("USD", "EUR", "GBP"):
                if code in up:
                    currency = code
                    break
        return amount, currency


    def merchant_from_sender(frm: str, subject: str) -> str:
        # Prefer a display name ("Acme Inc <no-reply@acme.com>"); else the domain.
        name = re.match(r"^\s*\"?([^\"<]+?)\"?\s*<", frm)
        if name:
            cand = name.group(1).strip()
            if cand and "@" not in cand:
                return cand
        domain = re.search(r"@([\w.-]+)", frm)
        if domain:
            host = domain.group(1).split(".")
            if len(host) >= 2:
                return host[-2]
        return subject.split(" - ")[0].strip()[:60]


    def stable_id(merchant: str, amount: str, date: str, subject: str) -> str:
        key = f"{merchant.lower()}|{amount}|{date}|{subject.lower()}"
        return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]


    def write_note(note: dict, msg_id: str) -> bool:
        amount, currency = extract_amount(note["body"])
        merchant = merchant_from_sender(note["from"], note["subject"])
        date = note["date"]
        nid = stable_id(merchant, amount, date, note["subject"])
        path = os.path.join(OUT, f"{nid}.md")
        if os.path.exists(path):
            return False  # idempotent: same (merchant, amount, date, subject)

        lines = [
            "---",
            f"date: {date}",
            f"merchant: {merchant}",
            f"amount: {amount}",
            f"currency: {currency}",
            "account: ",
            "institution: ",
            "category: ",
            "source: email",
            f"id: {nid}",
            f"gmail_message: {msg_id}",
            "---",
            "",
            f"# {merchant or '(charge)'} - {note['subject']}".rstrip(),
            "",
            f"- Date: {date}",
            f"- Merchant: {merchant}",
            f"- Amount: {amount} {currency}".rstrip(),
            f"- From: {note['from']}",
            f"- Source: email (gmail message {msg_id})",
            "",
            note["body"],
            "",
        ]
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines))
        return True


    def main() -> int:
        if not os.path.isdir(GMAIL):
            log("skipping: no gmail staging yet")
            return 0
        os.makedirs(OUT, exist_ok=True)

        scanned = 0
        written = 0
        for entry in os.listdir(GMAIL):
            if not entry.endswith(".md"):
                continue
            scanned += 1
            msg_id = entry[:-3]
            try:
                with open(os.path.join(GMAIL, entry), "r", encoding="utf-8", errors="ignore") as handle:
                    text = handle.read()
            except OSError:
                continue
            note = parse_note(text)
            if not is_charge(note):
                continue
            if write_note(note, msg_id):
                written += 1
        log(f"scanned {scanned} gmail note(s), wrote {written} charge note(s) to {OUT}")
        return 0


    sys.exit(main())
  '';

  simplefinConnector = pkgs.writeShellScript "kb-connector-finance-simplefin" ''
    set -uo pipefail
    set -a
    . /run/secrets/simplefin.env 2>/dev/null || true
    set +a
    exec ${pythonEnv}/bin/python ${simplefinScript}
  '';

  chargesConnector = pkgs.writeShellScript "kb-connector-finance-charges" ''
    set -uo pipefail
    exec ${pythonEnv}/bin/python ${chargesScript}
  '';

  mkConnector = name: exec: {
    "kb-connector-${name}" = {
      description = "KB connector: ${name} -> staging";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        ExecStart = exec;
      };
    };
  };

  mkTimer = name: onCalendar: {
    "kb-connector-${name}" = {
      description = "Schedule KB connector: ${name}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = onCalendar;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
in
{
  # Local-only finance namespace, owned by rathi so the connectors write and the
  # root indexer/graph can read.
  systemd.tmpfiles.rules = [
    "d ${financeDir} 0755 ${user} ${group} -"
    "d ${financeDir}/transactions 0755 ${user} ${group} -"
    "d ${financeDir}/charges 0755 ${user} ${group} -"
  ];

  systemd.services =
    (mkConnector "finance-simplefin" simplefinConnector)
    // (mkConnector "finance-charges" chargesConnector);

  systemd.timers =
    # SimpleFIN: every 3 hours (banks settle slowly; keep API calls light).
    (mkTimer "finance-simplefin" "0/3:00")
    # Charges: hourly, shortly after the gmail connector refreshes staging.
    // (mkTimer "finance-charges" "hourly");
}
