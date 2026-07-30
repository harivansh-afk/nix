from __future__ import annotations

import json
import re
import subprocess


KB_SEARCH = "/run/current-system/sw/bin/kb-search"
KB_GRAPH = "/run/current-system/sw/bin/kb-graph"
FINANCE_TERMS = re.compile(
    r"\b(account|bank|budget|charge|credit|debit|expense|finance|financial|"
    r"invoice|merchant|payment|receipt|spend|tax|transaction)\b",
    re.IGNORECASE,
)


def _run(command: list[str], timeout: int = 90) -> str:
    result = subprocess.run(
        command,
        capture_output=True,
        check=False,
        text=True,
        timeout=timeout,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        return json.dumps({"error": detail or f"command exited {result.returncode}"})
    return result.stdout.strip()


def _safe_query(value: str) -> str | None:
    query = value.strip()
    if not query:
        return None
    if FINANCE_TERMS.search(query):
        return None
    return query


def _is_finance(value: object) -> bool:
    return "finance" in str(value).lower() or bool(FINANCE_TERMS.search(str(value)))


def _filter_vector_output(output: str) -> str:
    rows = []
    for line in output.splitlines():
        match = re.match(r"^\[([^\]]+)\]", line)
        if (match and _is_finance(match.group(1))) or _is_finance(line):
            continue
        rows.append(line)
    return "\n".join(rows)


def _filter_graph_output(output: str) -> str:
    try:
        payload = json.loads(output)
    except json.JSONDecodeError:
        return json.dumps({"error": "kb-graph returned invalid JSON"})

    if isinstance(payload.get("matches"), list):
        payload["matches"] = [
            item
            for item in payload["matches"]
            if not any(_is_finance(value) for value in item.get("datasets", []))
        ]
    if isinstance(payload.get("sources"), list):
        payload["sources"] = [
            item
            for item in payload["sources"]
            if not _is_finance(item.get("dataset", ""))
            and not _is_finance(item.get("text", ""))
        ]
    return json.dumps(payload, ensure_ascii=False)


def _blocked() -> str:
    return json.dumps(
        {
            "error": (
                "Finance data is local-only and unavailable to this cloud-backed "
                "Hermes session."
            )
        }
    )


def register(ctx):
    search_schema = {
        "name": "kb_search",
        "description": (
            "Search Hari's local Cognee vector database for notes, documents, "
            "email, calendar, repositories, research, and saved items. Use this "
            "before asking Hari for information that may already be indexed."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Natural-language semantic search query.",
                }
            },
            "required": ["query"],
        },
    }

    resolve_schema = {
        "name": "kb_graph_resolve",
        "description": (
            "Resolve a rough mention to entities in the Cognee knowledge graph. "
            "Use after vector search when relationships or provenance matter."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "mention": {
                    "type": "string",
                    "description": "Person, project, organization, place, or concept.",
                },
                "limit": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 20,
                    "default": 8,
                },
            },
            "required": ["mention"],
        },
    }

    source_schema = {
        "name": "kb_graph_source",
        "description": (
            "Retrieve source-document chunks for a resolved Cognee entity. "
            "Use source text as ground truth instead of graph edge labels."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "entity": {
                    "type": "string",
                    "description": "Exact entity name or slug from kb_graph_resolve.",
                },
                "limit": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 20,
                    "default": 5,
                },
            },
            "required": ["entity"],
        },
    }

    def search(params, **kwargs):
        del kwargs
        query = _safe_query(str(params.get("query", "")))
        if query is None:
            return _blocked()
        return _filter_vector_output(_run([KB_SEARCH, query]))

    def resolve(params, **kwargs):
        del kwargs
        mention = _safe_query(str(params.get("mention", "")))
        if mention is None:
            return _blocked()
        limit = max(1, min(int(params.get("limit", 8)), 20))
        return _filter_graph_output(
            _run([KB_GRAPH, "resolve", mention, "-k", str(limit)])
        )

    def source(params, **kwargs):
        del kwargs
        entity = _safe_query(str(params.get("entity", "")))
        if entity is None:
            return _blocked()
        limit = max(1, min(int(params.get("limit", 5)), 20))
        return _filter_graph_output(
            _run([KB_GRAPH, "source", entity, "-k", str(limit)])
        )

    ctx.register_tool(
        name="kb_search",
        toolset="cognee",
        schema=search_schema,
        handler=search,
        description="Search the local Cognee vector database.",
    )
    ctx.register_tool(
        name="kb_graph_resolve",
        toolset="cognee",
        schema=resolve_schema,
        handler=resolve,
        description="Resolve an entity in the local Cognee graph.",
    )
    ctx.register_tool(
        name="kb_graph_source",
        toolset="cognee",
        schema=source_schema,
        handler=source,
        description="Retrieve source chunks for a Cognee graph entity.",
    )
