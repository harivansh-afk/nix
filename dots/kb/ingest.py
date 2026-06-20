#!/usr/bin/env python3
"""
KB ingestion pipeline - Slice 1.

Run via the cognee venv wrapper:
    cognee-env python ingest.py [--dry-run] [--state-file PATH]

# INTEGRATION SEAM: the exact invocation prefix (cognee-env, a venv activate,
# or a direct path to the venv python) is configured in kb-ingest.nix.  Only
# that file needs updating when the venv path is finalised.

Corpus (hard-coded here; adjust below if paths change):
    /home/rathi/Documents/Git/nvim-wiki
    /home/rathi/Documents/Git/tmux-wiki
    /home/rathi/Documents/Downloads/documents/readings
    /home/rathi/Documents/Downloads/documents/school-career

Denylist:  dots/kb/denylist.txt (loaded at runtime relative to this file).
State file: /var/lib/cognee/ingest-state.json  (override via --state-file).
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CORPUS_DIRS: list[Path] = [
    Path("/home/rathi/Documents/Git/nvim-wiki"),
    Path("/home/rathi/Documents/Git/tmux-wiki"),
    Path("/home/rathi/Documents/Downloads/documents/readings"),
    Path("/home/rathi/Documents/Downloads/documents/school-career"),
]

ALLOWED_EXTENSIONS: set[str] = {".md", ".markdown", ".txt", ".pdf"}

DEFAULT_STATE_FILE = Path("/var/lib/cognee/ingest-state.json")

# Cognee dataset name for Slice-1 corpus
DATASET_NAME = "personal-kb-slice1"

# ---------------------------------------------------------------------------
# Denylist loading
# ---------------------------------------------------------------------------

def load_denylist(denylist_path: Optional[Path] = None) -> list[str]:
    """
    Load denied path segments from the denylist file.
    Returns a list of strings; a file is skipped if any segment of its
    absolute path contains any of these strings.
    Always includes '.git' and 'node_modules' as hard-coded fallbacks
    even if the file is missing (fail-safe).
    """
    hard_coded = [".git", "node_modules"]
    if denylist_path is None:
        denylist_path = Path(__file__).parent / "denylist.txt"

    patterns: list[str] = list(hard_coded)
    if not denylist_path.exists():
        print(f"[WARN] denylist not found at {denylist_path}; using hard-coded entries only", file=sys.stderr)
        return patterns

    with denylist_path.open() as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line not in patterns:
                patterns.append(line)

    return patterns


def is_denied(path: Path, deny_segments: list[str]) -> bool:
    """
    Return True (deny) if any component of the absolute path matches a
    deny segment, or if any component starts with '.' (hidden/dotfile).
    Fail-safe: any exception returns True (deny).
    """
    try:
        parts = path.resolve().parts
        for part in parts:
            # Dotfile / hidden dir check (but allow the root '/')
            if part.startswith(".") and part not in {".", "/"}:
                return True
            for segment in deny_segments:
                if segment in part:
                    return True
        return False
    except Exception as exc:  # noqa: BLE001
        print(f"[WARN] deny-check error for {path}: {exc}; skipping (fail-safe)", file=sys.stderr)
        return True


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def walk_corpus(corpus_dirs: list[Path], deny_segments: list[str]) -> tuple[list[Path], int]:
    """
    Recursively walk corpus dirs; return (allowed_files, denied_count).
    Skips unsupported extensions silently.
    """
    allowed: list[Path] = []
    denied_count = 0

    for root_dir in corpus_dirs:
        if not root_dir.exists():
            print(f"[WARN] corpus dir missing, skipping: {root_dir}", file=sys.stderr)
            continue
        for dirpath, dirnames, filenames in os.walk(root_dir):
            dp = Path(dirpath)
            # Prune denied directories in-place so os.walk doesn't descend
            dirnames[:] = [
                d for d in dirnames
                if not is_denied(dp / d, deny_segments)
            ]
            for fname in filenames:
                fpath = dp / fname
                if fpath.suffix.lower() not in ALLOWED_EXTENSIONS:
                    continue
                if is_denied(fpath, deny_segments):
                    denied_count += 1
                    continue
                allowed.append(fpath)

    return allowed, denied_count


# ---------------------------------------------------------------------------
# Content hashing
# ---------------------------------------------------------------------------

def file_hash(path: Path) -> str:
    """Return SHA-256 hex digest of file contents."""
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# State (incremental / idempotent tracking)
# ---------------------------------------------------------------------------

def load_state(state_file: Path) -> dict[str, dict]:
    """
    Load ingestion state from JSON.
    Schema: { "<absolute-path>": {"mtime": float, "sha256": str} }
    """
    if not state_file.exists():
        return {}
    try:
        with state_file.open() as fh:
            return json.load(fh)
    except Exception as exc:  # noqa: BLE001
        print(f"[WARN] could not read state file {state_file}: {exc}; starting fresh", file=sys.stderr)
        return {}


def save_state(state: dict, state_file: Path) -> None:
    state_file.parent.mkdir(parents=True, exist_ok=True)
    tmp = state_file.with_suffix(".tmp")
    with tmp.open("w") as fh:
        json.dump(state, fh, indent=2)
    tmp.replace(state_file)


def needs_ingest(path: Path, state: dict) -> bool:
    """True if file is new, mtime changed, or hash changed."""
    key = str(path.resolve())
    if key not in state:
        return True
    entry = state[key]
    try:
        current_mtime = path.stat().st_mtime
    except OSError:
        return True
    if abs(current_mtime - entry.get("mtime", 0)) > 0.001:
        # mtime changed - re-check hash
        return file_hash(path) != entry.get("sha256", "")
    return False


# ---------------------------------------------------------------------------
# PDF text extraction (optional; skips gracefully if unavailable)
# ---------------------------------------------------------------------------

def extract_pdf_text(path: Path) -> Optional[str]:
    """
    Attempt to extract text from a PDF.  Returns None if no library is
    available - the caller will skip the file gracefully.
    """
    # Try pypdf first, then pdfminer as fallback
    try:
        import pypdf  # type: ignore

        reader = pypdf.PdfReader(str(path))
        pages = [page.extract_text() or "" for page in reader.pages]
        text = "\n".join(pages).strip()
        return text if text else None
    except ImportError:
        pass
    except Exception as exc:  # noqa: BLE001
        print(f"[WARN] pypdf error on {path}: {exc}", file=sys.stderr)
        return None

    try:
        from pdfminer.high_level import extract_text as pdfminer_extract  # type: ignore

        text = pdfminer_extract(str(path)).strip()
        return text if text else None
    except ImportError:
        pass
    except Exception as exc:  # noqa: BLE001
        print(f"[WARN] pdfminer error on {path}: {exc}", file=sys.stderr)
        return None

    return None


# ---------------------------------------------------------------------------
# Cognee ingestion
# ---------------------------------------------------------------------------

async def ingest_file(path: Path) -> bool:
    """
    Add a single file to Cognee.
    Returns True on success, False on error.

    # VERIFY API: cognee.add() accepts a data argument that can be a string
    # (file path), a URL, or raw text depending on the version.  The dataset_name
    # kwarg groups documents. Verify the exact signature against the installed
    # cognee version before running for real.  Current assumption:
    #   await cognee.add(data, dataset_name=DATASET_NAME)
    # where `data` is either a Path/str (file path) or extracted text string.
    """
    import cognee  # type: ignore  # provided by cognee-env

    if path.suffix.lower() == ".pdf":
        text = extract_pdf_text(path)
        if text is None:
            print(f"  [SKIP-PDF] no extractor available: {path}")
            return False
        # VERIFY API: passing raw text string; some versions may need a dict
        # or a TextDocument wrapper.  Adjust if cognee.add() rejects plain str.
        data: str | Path = text
    else:
        data = path  # pass Path directly for text files

    try:
        # VERIFY API: signature may be cognee.add(data, dataset_name=...)
        # or cognee.add(data, datasetName=...) or positional.  Check current
        # cognee source / changelog.
        await cognee.add(data, dataset_name=DATASET_NAME)
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"  [ERROR] cognee.add failed for {path}: {exc}", file=sys.stderr)
        return False


async def run_cognify() -> None:
    """
    Build/update the knowledge graph for the dataset.

    # VERIFY API: cognee.cognify() may accept a dataset_name filter in newer
    # versions.  If available, pass dataset_name=DATASET_NAME to limit scope.
    """
    import cognee  # type: ignore

    # VERIFY API: check whether cognify() accepts dataset_name kwarg.
    await cognee.cognify()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ingest personal KB corpus into Cognee (Slice 1)."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List what WOULD be ingested without calling Cognee. Safe to run anytime.",
    )
    parser.add_argument(
        "--state-file",
        type=Path,
        default=DEFAULT_STATE_FILE,
        help=f"Path to incremental state JSON (default: {DEFAULT_STATE_FILE})",
    )
    parser.add_argument(
        "--denylist",
        type=Path,
        default=None,
        help="Path to denylist.txt (default: same dir as this script)",
    )
    args = parser.parse_args()

    # --- Load denylist ---
    deny_segments = load_denylist(args.denylist)
    print(f"Denylist: {len(deny_segments)} segments loaded")

    # --- Walk corpus ---
    print("Scanning corpus...")
    candidate_files, denied_during_walk = walk_corpus(CORPUS_DIRS, deny_segments)
    print(f"  Found {len(candidate_files)} candidate files ({denied_during_walk} denied during walk)")

    # --- Load state ---
    state = load_state(args.state_file)

    # --- Determine what needs ingesting (dedup by mtime+hash) ---
    seen_hashes: set[str] = set()
    to_ingest: list[tuple[Path, str]] = []  # (path, sha256)
    skipped_unchanged = 0
    skipped_duplicate = 0

    for fpath in sorted(candidate_files):
        if not needs_ingest(fpath, state):
            skipped_unchanged += 1
            continue
        try:
            sha = file_hash(fpath)
        except OSError as exc:
            print(f"  [WARN] cannot hash {fpath}: {exc}; skipping", file=sys.stderr)
            continue
        if sha in seen_hashes:
            skipped_duplicate += 1
            continue
        seen_hashes.add(sha)
        to_ingest.append((fpath, sha))

    # --- Dry-run: just print ---
    if args.dry_run:
        print("\n=== DRY RUN - files that WOULD be ingested ===")
        for fpath, sha in to_ingest:
            print(f"  {fpath}  [{sha[:12]}]")
        print()
        print(f"Summary (dry-run):")
        print(f"  Would ingest : {len(to_ingest)}")
        print(f"  Skipped (unchanged/state): {skipped_unchanged}")
        print(f"  Skipped (content duplicate): {skipped_duplicate}")
        print(f"  Denied (denylist/hidden): {denied_during_walk}")
        return 0

    # --- Real ingest ---
    if not to_ingest:
        print("Nothing new to ingest.")
        print(f"  Skipped (unchanged): {skipped_unchanged}")
        print(f"  Skipped (duplicate): {skipped_duplicate}")
        print(f"  Denied: {denied_during_walk}")
        return 0

    print(f"\nIngesting {len(to_ingest)} files into Cognee dataset '{DATASET_NAME}'...")
    ingested_ok = 0
    ingested_fail = 0

    for fpath, sha in to_ingest:
        print(f"  -> {fpath}")
        ok = await ingest_file(fpath)
        if ok:
            ingested_ok += 1
            state[str(fpath.resolve())] = {
                "mtime": fpath.stat().st_mtime,
                "sha256": sha,
            }
        else:
            ingested_fail += 1

    # --- Build graph ---
    if ingested_ok > 0:
        print("\nRunning cognify() to build/update knowledge graph...")
        try:
            await run_cognify()
            print("  cognify() complete.")
        except Exception as exc:  # noqa: BLE001
            print(f"  [ERROR] cognify() failed: {exc}", file=sys.stderr)

    # --- Persist state ---
    save_state(state, args.state_file)
    print(f"State written to {args.state_file}")

    # --- Summary ---
    print()
    print("=== Ingestion summary ===")
    print(f"  Ingested (success) : {ingested_ok}")
    print(f"  Ingested (failed)  : {ingested_fail}")
    print(f"  Skipped (unchanged): {skipped_unchanged}")
    print(f"  Skipped (duplicate): {skipped_duplicate}")
    print(f"  Denied             : {denied_during_walk}")

    return 0 if ingested_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
