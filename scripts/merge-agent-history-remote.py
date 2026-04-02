#!/usr/bin/env python3
import json
import os
import shutil
import sys
from pathlib import Path


SOURCE_HOME = os.environ.get("AGENT_MERGE_SOURCE_HOME", "/Users/rathi")
TARGET_HOME = os.environ.get("AGENT_MERGE_TARGET_HOME", str(Path.home()))


def translate_path(value):
    if isinstance(value, str) and (value == SOURCE_HOME or value.startswith(f"{SOURCE_HOME}/")):
      return f"{TARGET_HOME}{value[len(SOURCE_HOME):]}"
    return value


def ensure_parent(path):
    path.parent.mkdir(parents=True, exist_ok=True)


def read_jsonl(path):
    if not path.exists():
        return []
    return [line.rstrip("\n") for line in path.read_text().splitlines() if line.strip()]


def write_text(path, text):
    ensure_parent(path)
    path.write_text(text)


def write_json(path, value):
    write_text(path, json.dumps(value, indent=2) + "\n")


def append_jsonl(path, lines):
    if not lines:
        return
    ensure_parent(path)
    with path.open("a") as handle:
        for line in lines:
            handle.write(line)
            handle.write("\n")


def translate_project_dir_name(name):
    if name == "-Users-rathi":
        return "-home-rathi"
    if name.startswith("-Users-rathi-"):
        return f"-home-rathi-{name[len('-Users-rathi-'):]}"
    return name


def translate_selected_fields(value, key=None):
    if isinstance(value, dict):
        return {child_key: translate_selected_fields(child_value, child_key) for child_key, child_value in value.items()}
    if isinstance(value, list):
        return [translate_selected_fields(item, key) for item in value]
    if isinstance(value, str) and key in {"cwd", "project", "projectPath", "originalPath", "rollout_path"}:
        return translate_path(value)
    return value


def extract_claude_prompt(message):
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                text = item.get("text") or item.get("content")
                if isinstance(text, str):
                    parts.append(text.strip())
        return " ".join(part for part in parts if part).strip()
    return ""


def build_claude_entry_from_file(path, project_path):
    first_prompt = ""
    created = ""
    modified = ""
    git_branch = ""
    is_sidechain = False
    message_count = 0

    for raw_line in path.read_text().splitlines():
        if not raw_line.strip():
            continue
        try:
            record = json.loads(raw_line)
        except json.JSONDecodeError:
            continue

        timestamp = record.get("timestamp")
        if timestamp and not created:
            created = timestamp
        if timestamp:
            modified = timestamp
        if record.get("gitBranch") and not git_branch:
            git_branch = record["gitBranch"]
        if record.get("isSidechain") is True:
            is_sidechain = True
        if record.get("type") in {"user", "assistant"}:
            message_count += 1
        if record.get("type") == "user" and not first_prompt:
            first_prompt = extract_claude_prompt(record.get("message"))

    return {
        "sessionId": path.stem,
        "fullPath": str(path),
        "fileMtime": int(path.stat().st_mtime * 1000),
        "firstPrompt": first_prompt,
        "messageCount": message_count,
        "created": created,
        "modified": modified,
        "gitBranch": git_branch,
        "projectPath": project_path,
        "isSidechain": is_sidechain,
    }


def merge_claude_history(stage_root, target_root):
    source = stage_root / "history.jsonl"
    target = target_root / "history.jsonl"
    existing_keys = set()

    for raw_line in read_jsonl(target):
        try:
            record = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        existing_keys.add((record.get("timestamp"), record.get("sessionId"), record.get("display"), record.get("project")))

    additions = []
    for raw_line in read_jsonl(source):
        try:
            record = translate_selected_fields(json.loads(raw_line))
        except json.JSONDecodeError:
            continue
        key = (record.get("timestamp"), record.get("sessionId"), record.get("display"), record.get("project"))
        if key in existing_keys:
            continue
        existing_keys.add(key)
        additions.append(json.dumps(record, ensure_ascii=False))

    append_jsonl(target, additions)


def merge_claude_transcripts(stage_root, target_root):
    source_dir = stage_root / "transcripts"
    target_dir = target_root / "transcripts"
    if not source_dir.exists():
        return
    target_dir.mkdir(parents=True, exist_ok=True)
    for source in source_dir.rglob("*"):
        if not source.is_file():
            continue
        destination = target_dir / source.relative_to(source_dir)
        ensure_parent(destination)
        shutil.copy2(source, destination)


def copy_transformed_claude_jsonl(source, destination):
    ensure_parent(destination)
    with source.open() as reader, destination.open("w") as writer:
        for raw_line in reader:
            if not raw_line.strip():
                writer.write(raw_line)
                continue
            try:
                record = translate_selected_fields(json.loads(raw_line))
            except json.JSONDecodeError:
                writer.write(raw_line)
                continue
            writer.write(json.dumps(record, ensure_ascii=False))
            writer.write("\n")


def merge_claude_projects(stage_root, target_root):
    source_projects = stage_root / "projects"
    target_projects = target_root / "projects"
    if not source_projects.exists():
        return
    target_projects.mkdir(parents=True, exist_ok=True)

    for source_project in source_projects.iterdir():
        if not source_project.is_dir():
            continue

        target_project = target_projects / translate_project_dir_name(source_project.name)
        target_project.mkdir(parents=True, exist_ok=True)

        for source in source_project.rglob("*"):
            if not source.is_file():
                continue
            relative = source.relative_to(source_project)
            if relative.name == "sessions-index.json":
                continue
            destination = target_project / relative
            if source.suffix == ".jsonl":
                copy_transformed_claude_jsonl(source, destination)
            else:
                ensure_parent(destination)
                shutil.copy2(source, destination)

        target_index = target_project / "sessions-index.json"
        existing_index = {}
        if target_index.exists():
            try:
                existing_index = json.loads(target_index.read_text())
            except json.JSONDecodeError:
                existing_index = {}

        source_index = {}
        stage_index_path = source_project / "sessions-index.json"
        if stage_index_path.exists():
            try:
                source_index = json.loads(stage_index_path.read_text())
            except json.JSONDecodeError:
                source_index = {}

        metadata_by_filename = {}
        for index_data in [existing_index, source_index]:
            for entry in index_data.get("entries", []):
                filename = Path(entry.get("fullPath", "")).name
                if not filename:
                    continue
                entry = translate_selected_fields(entry)
                entry["fullPath"] = str(target_project / filename)
                candidate = target_project / filename
                if candidate.exists():
                    entry["fileMtime"] = int(candidate.stat().st_mtime * 1000)
                metadata_by_filename[filename] = entry

        original_path = translate_path(source_index.get("originalPath") or existing_index.get("originalPath") or "")

        entries = []
        for candidate in sorted(target_project.glob("*.jsonl")):
            entry = metadata_by_filename.get(candidate.name)
            if entry is None:
                project_path = original_path
                if not project_path:
                    for raw_line in candidate.read_text().splitlines():
                        if not raw_line.strip():
                            continue
                        try:
                            record = json.loads(raw_line)
                        except json.JSONDecodeError:
                            continue
                        if isinstance(record.get("cwd"), str):
                            project_path = record["cwd"]
                            break
                entry = build_claude_entry_from_file(candidate, project_path)
            else:
                entry = {**entry, "fullPath": str(candidate), "fileMtime": int(candidate.stat().st_mtime * 1000)}
            entries.append(entry)
            if not original_path and entry.get("projectPath"):
                original_path = entry["projectPath"]

        write_json(
            target_index,
            {
                "version": 1,
                "entries": entries,
                "originalPath": original_path,
            },
        )


def merge_codex_history(stage_root, target_root):
    source = stage_root / "history.jsonl"
    target = target_root / "history.jsonl"
    existing_keys = set()

    for raw_line in read_jsonl(target):
        try:
            record = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        existing_keys.add((record.get("session_id"), record.get("ts"), record.get("text")))

    additions = []
    for raw_line in read_jsonl(source):
        try:
            record = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        key = (record.get("session_id"), record.get("ts"), record.get("text"))
        if key in existing_keys:
            continue
        existing_keys.add(key)
        additions.append(json.dumps(record, ensure_ascii=False))

    append_jsonl(target, additions)


def transform_codex_record(record):
    record = translate_selected_fields(record)

    if record.get("type") == "session_meta":
        payload = record.get("payload")
        if isinstance(payload, dict) and isinstance(payload.get("cwd"), str):
            payload["cwd"] = translate_path(payload["cwd"])

    if record.get("type") == "response_item":
        payload = record.get("payload")
        if isinstance(payload, dict) and payload.get("type") == "message":
            for item in payload.get("content", []):
                if isinstance(item, dict) and item.get("type") == "input_text" and isinstance(item.get("text"), str):
                    if "<environment_context>" in item["text"] and "<cwd>" in item["text"]:
                        item["text"] = item["text"].replace(SOURCE_HOME, TARGET_HOME)

    return record


def merge_codex_sessions(stage_root, target_root):
    source_dir = stage_root / "sessions"
    target_dir = target_root / "sessions"
    if not source_dir.exists():
        return
    target_dir.mkdir(parents=True, exist_ok=True)

    for source in source_dir.rglob("*"):
        if not source.is_file():
            continue
        destination = target_dir / source.relative_to(source_dir)
        ensure_parent(destination)
        with source.open() as reader, destination.open("w") as writer:
            for raw_line in reader:
                if not raw_line.strip():
                    writer.write(raw_line)
                    continue
                try:
                    record = transform_codex_record(json.loads(raw_line))
                except json.JSONDecodeError:
                    writer.write(raw_line)
                    continue
                writer.write(json.dumps(record, ensure_ascii=False))
                writer.write("\n")


def merge_codex_session_index(stage_root, target_root):
    source = stage_root / "session_index.jsonl"
    target = target_root / "session_index.jsonl"
    merged = {}

    for current in [target, source]:
        for raw_line in read_jsonl(current):
            try:
                record = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            identifier = record.get("id")
            if identifier:
                merged[identifier] = record

    ordered = sorted(merged.values(), key=lambda item: (item.get("updated_at") or "", item.get("id") or ""))
    write_text(target, "".join(f"{json.dumps(item, ensure_ascii=False)}\n" for item in ordered))


def copy_translated_text_tree(source_dir, target_dir):
    if not source_dir.exists():
        return
    for source in source_dir.rglob("*"):
        if not source.is_file():
            continue
        destination = target_dir / source.relative_to(source_dir)
        ensure_parent(destination)
        write_text(destination, source.read_text().replace(SOURCE_HOME, TARGET_HOME))


def split_markdown_sections(text, prefix):
    header_lines = []
    sections = []
    current = None

    for line in text.splitlines():
        if line.startswith(prefix):
            if current is not None:
                sections.append("\n".join(current).rstrip() + "\n")
            current = [line]
        elif current is None:
            header_lines.append(line)
        else:
            current.append(line)

    if current is not None:
        sections.append("\n".join(current).rstrip() + "\n")

    header = "\n".join(header_lines).rstrip()
    if header:
        header += "\n\n"
    return header, sections


def section_identity(section):
    return section.splitlines()[0].strip()


def merge_markdown_sections(target, source, prefix):
    if not source.exists():
        return

    source_text = source.read_text().replace(SOURCE_HOME, TARGET_HOME)
    source_header, source_sections = split_markdown_sections(source_text, prefix)

    if target.exists():
        target_text = target.read_text()
        target_header, target_sections = split_markdown_sections(target_text, prefix)
    else:
        target_header, target_sections = "", []

    header = target_header or source_header
    existing_ids = {section_identity(section) for section in target_sections}
    merged_sections = [section for section in source_sections if section_identity(section) not in existing_ids] + target_sections
    write_text(target, header + "\n".join(section.rstrip() for section in merged_sections if section).rstrip() + "\n")


def merge_unique_lines(target, source):
    if not source.exists():
        return

    source_lines = source.read_text().replace(SOURCE_HOME, TARGET_HOME).splitlines()
    target_lines = target.read_text().splitlines() if target.exists() else []
    existing = set(target_lines)
    merged = list(target_lines)
    for line in source_lines:
        if line not in existing:
            merged.append(line)
            existing.add(line)
    write_text(target, "\n".join(merged).rstrip() + "\n")


def merge_codex_memories(stage_root, target_root):
    source_dir = stage_root / "memories"
    target_dir = target_root / "memories"
    if not source_dir.exists():
        return
    target_dir.mkdir(parents=True, exist_ok=True)

    copy_translated_text_tree(source_dir / "rollout_summaries", target_dir / "rollout_summaries")
    merge_markdown_sections(target_dir / "raw_memories.md", source_dir / "raw_memories.md", "## Thread ")
    merge_markdown_sections(target_dir / "MEMORY.md", source_dir / "MEMORY.md", "# Task Group:")
    merge_unique_lines(target_dir / "memory_summary.md", source_dir / "memory_summary.md")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: merge-agent-history-remote.py <stage-root>")

    stage_root = Path(sys.argv[1]).expanduser()
    home = Path(TARGET_HOME)

    merge_claude_history(stage_root / ".claude", home / ".claude")
    merge_claude_transcripts(stage_root / ".claude", home / ".claude")
    merge_claude_projects(stage_root / ".claude", home / ".claude")

    merge_codex_history(stage_root / ".codex", home / ".codex")
    merge_codex_session_index(stage_root / ".codex", home / ".codex")
    merge_codex_sessions(stage_root / ".codex", home / ".codex")
    merge_codex_memories(stage_root / ".codex", home / ".codex")


if __name__ == "__main__":
    main()
