#!/usr/bin/env python3
"""downloads_connector.py - KB connector for ~/Documents/Downloads personal docs.

Walks the user's Downloads tree, extracts text from supported document types
(pdf, docx, xlsx, txt) and writes one normalized markdown note per source file
into /var/lib/kb/staging/downloads/, with frontmatter (source path, file type,
ingested timestamp, content hash). The hourly kb-ingest service then embeds the
staging area into pgvector (see modules/services/kb-ingest.nix). This script
only touches staging; it never modifies the kb-ingest hot path.

Media (mp4, mov, png, jpg, jpeg, heic, psd, otf) is skipped.

Content-hash dedupe: each note stores the source file's sha256 in frontmatter.
On rerun, if a note for that source already carries the same hash, the file is
left untouched (no re-extract, no rewrite).

PRIVACY DENYLIST (hard, enforced in code - per CLAUDE.md / TOOLS.md):
The directories below are absolutely excluded. We never read, extract, or stage
anything under them. This is enforced by path-prefix exclusion during the walk,
not by convention.
"""

from __future__ import annotations

import hashlib
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path.home() / "Documents" / "Downloads"
STAGING = Path("/var/lib/kb/staging/downloads")

# Hard privacy denylist: absolute directory prefixes that must never be read.
# Enforced in code (see _is_denied). Do not relax without updating CLAUDE.md.
DENYLIST = [
    ROOT / "security",
    ROOT / "documents" / "finance-tax",
    ROOT / "documents" / "travel-identity",
    ROOT / "documents" / "legal-business",
]

# Supported document extensions -> extractor dispatch happens in extract_text.
TEXT_EXTS = {".pdf", ".docx", ".xlsx", ".txt"}

# Media (and other binary) extensions we explicitly skip. Anything not in
# TEXT_EXTS is skipped anyway; this set just documents the expected media.
MEDIA_EXTS = {".mp4", ".mov", ".png", ".jpg", ".jpeg", ".heic", ".psd", ".otf"}


def _is_denied(path: Path) -> bool:
    """True if path is inside any denylisted directory (absolute prefix match)."""
    rp = path.resolve()
    for denied in DENYLIST:
        try:
            rp.relative_to(denied.resolve())
            return True
        except ValueError:
            continue
    return False


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def extract_pdf(path: Path) -> str:
    import fitz  # pymupdf

    parts = []
    with fitz.open(path) as doc:
        for page in doc:
            parts.append(page.get_text())
    return "\n".join(parts)


def extract_docx(path: Path) -> str:
    import docx

    d = docx.Document(str(path))
    return "\n".join(p.text for p in d.paragraphs)


def extract_xlsx(path: Path) -> str:
    import openpyxl

    wb = openpyxl.load_workbook(str(path), read_only=True, data_only=True)
    parts = []
    for ws in wb.worksheets:
        parts.append(f"## {ws.title}")
        for row in ws.iter_rows(values_only=True):
            cells = ["" if c is None else str(c) for c in row]
            if any(cells):
                parts.append("\t".join(cells))
    wb.close()
    return "\n".join(parts)


def extract_text(path: Path, ext: str) -> str:
    if ext == ".pdf":
        return extract_pdf(path)
    if ext == ".docx":
        return extract_docx(path)
    if ext == ".xlsx":
        return extract_xlsx(path)
    if ext == ".txt":
        return path.read_text(errors="ignore")
    raise ValueError(f"unsupported extension: {ext}")


def note_path(src: Path) -> Path:
    """Deterministic note name keyed on the source path (stable across reruns)."""
    digest = hashlib.sha256(str(src.resolve()).encode()).hexdigest()[:16]
    return STAGING / f"{src.stem}_{digest}.md"


def existing_hash(note: Path) -> str | None:
    """Read the content_hash from an existing note's frontmatter, if present."""
    if not note.exists():
        return None
    try:
        with note.open(errors="ignore") as f:
            for line in f:
                if line.startswith("content_hash:"):
                    return line.split(":", 1)[1].strip()
                if line.strip() == "---" and f.tell() > 4:
                    # end of frontmatter without a hash
                    break
    except OSError:
        return None
    return None


def write_note(src: Path, ext: str, content_hash: str, text: str) -> None:
    STAGING.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    note = note_path(src)
    body = (
        "---\n"
        f"source: {src}\n"
        f"file_type: {ext.lstrip('.')}\n"
        f"ingested: {ts}\n"
        f"content_hash: {content_hash}\n"
        "source_kind: downloads\n"
        "---\n\n"
        f"# {src.name}\n\n"
        f"{text.strip()}\n"
    )
    tmp = note.with_suffix(note.suffix + ".tmp")
    tmp.write_text(body)
    tmp.replace(note)


def main() -> int:
    if not ROOT.exists():
        print(f"downloads: {ROOT} does not exist; nothing to do")
        return 0

    written = skipped = denied = unchanged = 0

    for dirpath, dirnames, filenames in os.walk(ROOT):
        d = Path(dirpath)
        # Prune denylisted subtrees in place so we never descend into them.
        dirnames[:] = [
            sub for sub in dirnames if not _is_denied(d / sub)
        ]
        # Skip hidden directories (.git, etc.) for parity with the KB denylist.
        dirnames[:] = [sub for sub in dirnames if not sub.startswith(".")]

        if _is_denied(d):
            continue

        for name in filenames:
            f = d / name
            if _is_denied(f):
                denied += 1
                continue
            ext = f.suffix.lower()
            if ext not in TEXT_EXTS:
                skipped += 1
                continue
            try:
                h = sha256_file(f)
            except OSError:
                skipped += 1
                continue
            if existing_hash(note_path(f)) == h:
                unchanged += 1
                continue
            try:
                text = extract_text(f, ext)
            except Exception as e:  # noqa: BLE001 - one bad file shouldn't abort
                print(f"downloads: extract failed for {f}: {e}", file=sys.stderr)
                skipped += 1
                continue
            write_note(f, ext, h, text)
            written += 1

    print(
        f"downloads: wrote {written}, unchanged {unchanged}, "
        f"skipped {skipped}, denied {denied} -> {STAGING}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
