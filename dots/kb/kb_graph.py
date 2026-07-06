"""kb-graph: read-only traversal of the Cognee knowledge graph.

Companion to kb_vec.py (kb-search). Where kb-search does flat vector similarity,
this exposes the *graph*: the entities Cognee extracted from the indexed notes,
email, calendar, finance, repos, and downloads, and the relations between them.

Why this exists: the graph holds connections that flat vector search cannot
surface. Two entities can sit far apart in embedding space yet be linked in the
graph in a couple of hops, and the graph points at the exact source document
that ties them together.

Design (see dots/hermes/TOOLS.md "Knowledge graph" for the agent-facing contract):

  The graph lives in BOTH Kuzu (the graph engine) and Postgres (a full mirror:
  the `nodes` and `edges` tables plus per-type pgvector collections). Kuzu state
  is root-owned (/var/lib/cognee is 0750), but the Postgres mirror is reachable
  over loopback with the same low-value cognee creds kb-search already uses. So
  this tool talks ONLY to Postgres: it needs no root, no Kuzu lock, and works for
  the rathi user / Hermes exactly like kb-search.

  Node identity: `nodes.slug` is the stable graph id (a node has many `nodes`
  rows across datasets/runs, all sharing one slug); `nodes.label` is the name.
  `edges.source_node_id` / `destination_node_id` reference the slug. The
  `Entity_name` pgvector table keys on the slug too (`payload->>'text'` is the
  name), which is what makes semantic `resolve` possible.

Reliability contract the primitives are built around, learned from the live graph:
  - Node existence and connectivity are RELIABLE.
  - Edge *names* are NOISY: the local extraction model invents them and sometimes
    inverts direction. Treat an edge as "these two are related", not as a typed
    fact you can quote.
  - The ground truth is the source text. `source` returns the real document
    chunks so the caller reads sentences instead of trusting a label.

Four subcommands, all emitting JSON on stdout:
  resolve <mention>   fuzzy mention -> ranked real entities (exact + substring +
                      semantic via pgvector), each with slug, degree, datasets.
  neighbors <node>    what a node connects to, grouped and deduped.
  connect <a> <b>     shortest relation path between two nodes (BFS, undirected).
  source <node>       the real source-document chunks that mention the node.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
import uuid

import psycopg2

EMBED_URL = "http://127.0.0.1:18200/v1/embeddings"
EMBED_MODEL = "qwen3-embedding-0.6b"
PG = dict(host="127.0.0.1", port=5432, dbname="cognee", user="cognee", password="cognee")

# Node .type values that are real semantic entities (people, orgs, places,
# concepts), as opposed to Cognee's structural nodes (DocumentChunk, TextSummary,
# TextDocument, EntityType, NodeSet). resolve only ever returns these.
ENTITY_TYPE = "Entity"
CHUNK_TYPE = "DocumentChunk"

# Structural nodes carry Cognee's document tree, not semantic meaning. neighbors
# hides them by default (they show as raw chunk ids, not names); `source` is the
# right tool for their text.
STRUCTURAL_TYPES = ("DocumentChunk", "TextSummary", "TextDocument", "NodeSet")

# Structural relations wire the document tree and dataset membership. Every doc in
# a dataset shares `belongs_to_set -> <dataset>`, so traversing these produces
# trivial "connections" through a hub. `connect` and default `neighbors` skip them
# so paths are real entity-to-entity relations.
STRUCTURAL_RELS = (
    "belongs_to_set",
    "contains",
    "is_part_of",
    "made_from",
    "source_of_extraction_to",
)


def die(msg: str) -> None:
    """Emit a typed error to stderr and exit non-zero (no silent fallback)."""
    print(json.dumps({"error": msg}), file=sys.stderr)
    raise SystemExit(1)


def connect_pg() -> psycopg2.extensions.connection:
    """Open the loopback Cognee Postgres, or fail with a typed error."""
    try:
        return psycopg2.connect(**PG)
    except psycopg2.Error as exc:
        die(f"cannot reach cognee Postgres on 127.0.0.1:5432: {exc}")


def embed(text: str) -> str:
    """Embed one string via the local llama.cpp server; return a pgvector literal.

    Returns the '[f, f, ...]' string pgvector's `<=>` operator accepts directly.
    """
    body = json.dumps({"input": text, "model": EMBED_MODEL}).encode()
    req = urllib.request.Request(EMBED_URL, body, {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            vec = json.load(resp)["data"][0]["embedding"]
    except (urllib.error.URLError, KeyError, IndexError) as exc:
        die(f"embedding server unreachable at {EMBED_URL}: {exc}")
    return str(vec)


# --- shared graph helpers --------------------------------------------------


def datasets_for(cur, slug: str) -> list[str]:
    """Which source datasets a node belongs to (gmail, finance, downloads, ...)."""
    cur.execute(
        """
        select distinct d.name
        from nodes n join datasets d on d.id = n.dataset_id
        where n.slug = %s and d.name is not null
        order by d.name
        """,
        (slug,),
    )
    return [row[0] for row in cur.fetchall()]


def degree_of(cur, slug: str) -> int:
    """Distinct-edge degree of a node (dedupes the per-dataset/run edge copies)."""
    cur.execute(
        """
        select count(*) from (
            select distinct source_node_id, destination_node_id, relationship_name
            from edges where source_node_id = %s or destination_node_id = %s
        ) t
        """,
        (slug, slug),
    )
    return cur.fetchone()[0]


def name_match(cur, mention: str, limit: int) -> list[dict]:
    """Deterministic name matches only: exact lowercased, then substring.

    No semantic fallback: this is how a *known* node is located by name for
    traversal, so a nonsense mention must return nothing rather than the nearest
    embedding neighbour. Semantic discovery lives in resolve() instead.
    """
    found: dict[str, dict] = {}
    cur.execute(
        "select distinct slug, label from nodes where type = %s and lower(label) = lower(%s)",
        (ENTITY_TYPE, mention),
    )
    for slug, name in cur.fetchall():
        found.setdefault(str(slug), {"slug": str(slug), "name": name, "match": "exact"})

    cur.execute(
        """
        select distinct slug, label from nodes
        where type = %s and lower(label) like lower(%s) and lower(label) <> lower(%s)
        limit %s
        """,
        (ENTITY_TYPE, f"%{mention}%", mention, limit),
    )
    for slug, name in cur.fetchall():
        found.setdefault(str(slug), {"slug": str(slug), "name": name, "match": "substring"})
    return list(found.values())[:limit]


def resolve_slugs(cur, mention: str, limit: int = 8) -> list[dict]:
    """Resolve a fuzzy mention to real entity nodes, best match first.

    Merges three strategies and dedupes by slug, preferring the strongest match:
      1. exact     - lowercased label equality (most trustworthy)
      2. substring - label contains the mention (handles partial names)
      3. semantic  - pgvector nearest neighbours over entity-name embeddings
                     (handles a descriptive mention that is not the literal name)
    """
    found: dict[str, dict] = {}
    for m in name_match(cur, mention, limit):
        m["distance"] = 0.0 if m["match"] == "exact" else None
        found[m["slug"]] = m

    query_vec = embed(mention)
    cur.execute(
        """
        select en.id, en.payload->>'text', en.vector <=> %s as dist
        from "Entity_name" en
        order by en.vector <=> %s
        limit %s
        """,
        (query_vec, query_vec, limit),
    )
    for slug, name, dist in cur.fetchall():
        found.setdefault(
            str(slug),
            {"slug": str(slug), "name": name, "match": "semantic", "distance": round(float(dist), 4)},
        )

    rank = {"exact": 0, "substring": 1, "semantic": 2}
    ordered = sorted(
        found.values(),
        key=lambda m: (rank[m["match"]], m["distance"] if m["distance"] is not None else 0.5),
    )
    return ordered[:limit]


def slugs_for_node(cur, node: str) -> list[str]:
    """Turn a CLI node argument into slug(s) for traversal.

    A raw slug passes through; otherwise match by name (exact + substring only).
    Deliberately no semantic fallback, so an unmatched name yields no traversal
    rather than silently operating on an unrelated entity.
    """
    try:
        uuid.UUID(node)
    except ValueError:
        pass
    else:
        cur.execute("select 1 from nodes where slug = %s limit 1", (node,))
        if cur.fetchone():
            return [node]
    return [m["slug"] for m in name_match(cur, node, limit=3)]


# --- subcommands -----------------------------------------------------------


def cmd_resolve(args) -> dict:
    con = connect_pg()
    cur = con.cursor()
    matches = resolve_slugs(cur, args.mention, limit=args.k)
    for m in matches:
        m["datasets"] = datasets_for(cur, m["slug"])
        m["degree"] = degree_of(cur, m["slug"])
    return {"query": args.mention, "matches": matches}


def cmd_neighbors(args) -> dict:
    con = connect_pg()
    cur = con.cursor()
    slugs = slugs_for_node(cur, args.node)
    if not slugs:
        return {"query": args.node, "resolved": [], "neighbors": []}

    rel_clause = "and e.relationship_name ilike %(rel)s" if args.rel else ""
    # Hide structural document-tree nodes unless --all; they render as raw ids.
    type_clause = "" if args.all else "and nb.type not in %(structural_types)s"
    params = {
        "slugs": tuple(slugs),
        "rel": f"%{args.rel}%" if args.rel else None,
        "structural_types": STRUCTURAL_TYPES,
        "k": args.k,
    }

    # Both directions in one pass: out-edges (node is the source of the edge) and
    # in-edges (node is the destination). Named params keep the two branches tidy.
    cur.execute(
        f"""
        select distinct direction, rel, edge_label, neighbor, type from (
            select 'out' as direction, e.relationship_name as rel, e.label as edge_label,
                   nb.label as neighbor, nb.type as type
            from edges e join nodes nb on nb.slug = e.destination_node_id
            where e.source_node_id in %(slugs)s {rel_clause} {type_clause}
            union
            select 'in' as direction, e.relationship_name, e.label,
                   nb.label, nb.type
            from edges e join nodes nb on nb.slug = e.source_node_id
            where e.destination_node_id in %(slugs)s {rel_clause} {type_clause}
        ) t
        where neighbor is not null
        order by direction, rel, neighbor
        limit %(k)s
        """,
        params,
    )
    neighbors = [
        {"direction": d, "relationship": rel, "edge_label": lbl, "neighbor": name, "type": typ}
        for d, rel, lbl, name, typ in cur.fetchall()
    ]
    return {"query": args.node, "resolved": slugs, "neighbors": neighbors}


def cmd_connect(args) -> dict:
    con = connect_pg()
    cur = con.cursor()
    src = slugs_for_node(cur, args.a)
    dst = set(slugs_for_node(cur, args.b))
    if not src or not dst:
        return {"from": args.a, "to": args.b, "path": None, "note": "endpoint did not resolve"}

    # Undirected BFS over the edge mirror. Frontier is a set of slugs; we record
    # each hop's (prev-slug, relationship) so the path can be rendered by name.
    seen: set[str] = set(src)
    parent: dict[str, tuple[str, str]] = {}
    frontier = list(src)
    hit: str | None = next((s for s in src if s in dst), None)

    hops = 0
    while frontier and hit is None and hops < args.max_hops:
        cur.execute(
            """
            select source_node_id, destination_node_id, relationship_name
            from edges
            where (source_node_id in %s or destination_node_id in %s)
              and relationship_name not in %s
            """,
            (tuple(frontier), tuple(frontier), STRUCTURAL_RELS),
        )
        rows = cur.fetchall()
        nxt: list[str] = []
        fset = set(frontier)
        for s, d, rel in rows:
            s, d = str(s), str(d)
            for a, b in ((s, d), (d, s)):
                if a in fset and b not in seen:
                    seen.add(b)
                    parent[b] = (a, rel)
                    nxt.append(b)
                    if b in dst:
                        hit = b
        frontier = nxt
        hops += 1

    if hit is None:
        return {"from": args.a, "to": args.b, "path": None,
                "note": f"no path within {args.max_hops} hops"}

    # Walk parents back to a source, then render slug -> name.
    chain: list[tuple[str, str | None]] = []
    node = hit
    while node in parent:
        prev, rel = parent[node]
        chain.append((node, rel))
        node = prev
    chain.append((node, None))
    chain.reverse()

    def name_of(slug: str) -> str:
        cur.execute("select label from nodes where slug = %s limit 1", (slug,))
        row = cur.fetchone()
        return row[0] if row else slug

    path = [{"node": name_of(s), "via": rel} for s, rel in chain]
    return {"from": args.a, "to": args.b, "hops": len(path) - 1, "path": path}


def cmd_source(args) -> dict:
    con = connect_pg()
    cur = con.cursor()
    slugs = slugs_for_node(cur, args.node)
    if not slugs:
        return {"query": args.node, "resolved": [], "sources": []}

    cur.execute(
        """
        select distinct
            c.attributes->>'source_node_set' as dataset,
            c.attributes->>'source_content_hash' as content_hash,
            c.attributes->>'text' as text
        from edges e
        join nodes c on c.slug = e.source_node_id or c.slug = e.destination_node_id
        where (e.source_node_id in %s or e.destination_node_id in %s)
          and c.type = %s and c.attributes->>'text' is not null
        limit %s
        """,
        (tuple(slugs), tuple(slugs), CHUNK_TYPE, args.k),
    )
    sources = []
    for dataset, content_hash, text in cur.fetchall():
        text = text.strip()
        if not args.full and len(text) > 700:
            text = text[:700] + " ..."
        sources.append({"dataset": dataset, "content_hash": content_hash, "text": text})
    return {"query": args.node, "resolved": slugs, "sources": sources}


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="kb-graph", description="Read-only traversal of the Cognee knowledge graph."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("resolve", help="fuzzy mention -> ranked real entities")
    p.add_argument("mention")
    p.add_argument("-k", type=int, default=8, help="max matches (default 8)")
    p.set_defaults(fn=cmd_resolve)

    p = sub.add_parser("neighbors", help="what a node connects to")
    p.add_argument("node", help="entity name or slug")
    p.add_argument("-k", type=int, default=40, help="max neighbors (default 40)")
    p.add_argument("--rel", help="filter to relationships matching this substring")
    p.add_argument("--all", action="store_true",
                   help="include structural document-tree nodes (hidden by default)")
    p.set_defaults(fn=cmd_neighbors)

    p = sub.add_parser("connect", help="shortest relation path between two nodes")
    p.add_argument("a", help="first entity name or slug")
    p.add_argument("b", help="second entity name or slug")
    p.add_argument("--max-hops", type=int, default=4, dest="max_hops")
    p.set_defaults(fn=cmd_connect)

    p = sub.add_parser("source", help="source-document chunks that mention the node")
    p.add_argument("node", help="entity name or slug")
    p.add_argument("-k", type=int, default=5, help="max chunks (default 5)")
    p.add_argument("--full", action="store_true", help="do not truncate chunk text")
    p.set_defaults(fn=cmd_source)

    args = parser.parse_args()
    result = args.fn(args)
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
