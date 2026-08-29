"""kb_vec.py - flat hybrid search over the personal KB.

ingest: walk /var/lib/kb/staging/**/*.md, chunk on text boundaries with
        overlap, embed via the local llama.cpp server, full reload of the
        kb_vec table (TRUNCATE + insert; idempotent, ~seconds on GPU).
search: hybrid retrieval, two arms fused with reciprocal rank fusion:
        - semantic: pgvector cosine over an HNSW index. The query (and only
          the query) gets the Qwen3-Embedding instruction prefix; documents
          are embedded plain, per the model's asymmetric usage contract.
        - lexical:  Postgres full-text (websearch_to_tsquery over a GIN
          expression index). This is what makes rare-term / name / one-word
          queries work; a 0.6b embedder alone misses them.

History: the first version used an ivfflat index with default lists=100 and
default probes=1, which scanned ~1% of the table: measured recall@10 was 8%.
HNSW at this scale is near-exact. Do not reintroduce ivfflat.
"""

import argparse
import glob
import json
import os
import time
import urllib.request

import psycopg2

EMBED = "http://127.0.0.1:18200/v1/embeddings"
PG = dict(host="127.0.0.1", port=5432, dbname="cognee", user="cognee", password="cognee")

QUERY_INSTRUCT = (
    "Instruct: Given a search query, retrieve relevant passages from the user's "
    "personal notes, email, calendar, finance records, repos, and documents\nQuery: "
)

CHUNK_TARGET = 1600
CHUNK_OVERLAP = 200
TOPK = 8
CANDIDATES = 40
RRF_K = 60
EXCERPT = 240


def embed(texts):
    body = json.dumps({"input": texts, "model": "qwen3-embedding-0.6b"}).encode()
    r = urllib.request.urlopen(
        urllib.request.Request(EMBED, body, {"Content-Type": "application/json"}), timeout=120
    )
    return [d["embedding"] for d in json.load(r)["data"]]


def chunks(t, target=CHUNK_TARGET, overlap=CHUNK_OVERLAP):
    """Boundary-aware overlapping chunks: prefer paragraph > line > word breaks
    in the tail 40% of each window; always advances, always terminates."""
    t = t.strip()
    if len(t) <= target:
        return [t] if t else []
    out, i, n = [], 0, len(t)
    while i < n:
        j = min(i + target, n)
        if j < n:
            for sep in ("\n\n", "\n", " "):
                k = t.rfind(sep, i + int(target * 0.6), j)
                if k != -1:
                    j = k
                    break
        piece = t[i:j].strip()
        if piece:
            out.append(piece)
        if j >= n:
            break
        i = max(j - overlap, i + 1)
    return out


def ingest():
    con = psycopg2.connect(**PG)
    cur = con.cursor()
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
    cur.execute(
        "CREATE TABLE IF NOT EXISTS kb_vec(id bigserial primary key, source text,"
        " path text, chunk int, txt text, emb vector(1024))"
    )
    cur.execute("DROP INDEX IF EXISTS kb_vec_idx")
    cur.execute("TRUNCATE kb_vec")
    con.commit()
    files = glob.glob("/var/lib/kb/staging/**/*.md", recursive=True)
    t0 = time.time()
    n = 0
    batch, meta = [], []

    def flush():
        nonlocal n
        if not batch:
            return
        embs = embed(batch)
        for (src, path, ci, txt), e in zip(meta, embs):
            cur.execute(
                "INSERT INTO kb_vec(source,path,chunk,txt,emb) VALUES(%s,%s,%s,%s,%s)",
                (src, path, ci, txt, str(e)),
            )
            n += 1
        con.commit()
        batch.clear()
        meta.clear()

    for f in files:
        src = f.split("/var/lib/kb/staging/")[-1].split("/")[0]
        txt = open(f, errors="ignore").read()
        for ci, c in enumerate(chunks(txt)):
            batch.append(c)
            meta.append((src, f, ci, c))
            if len(batch) >= 32:
                flush()
    flush()
    cur.execute("CREATE INDEX IF NOT EXISTS kb_vec_hnsw ON kb_vec USING hnsw (emb vector_cosine_ops)")
    cur.execute("CREATE INDEX IF NOT EXISTS kb_vec_fts ON kb_vec USING gin (to_tsvector('english', txt))")
    con.commit()
    print(f"INDEXED {n} chunks from {len(files)} docs in {time.time() - t0:.1f}s")


def search(
    q,
    *,
    exclude_sources=(),
    limit=TOPK,
    excerpt_chars=EXCERPT,
    json_output=False,
):
    con = psycopg2.connect(**PG)
    cur = con.cursor()

    e = str(embed([QUERY_INSTRUCT + q])[0])
    cur.execute("SET hnsw.ef_search = 100")
    cur.execute(
        """
        SELECT id FROM kb_vec
        WHERE NOT (source = ANY(%s))
        ORDER BY emb <=> %s
        LIMIT %s
        """,
        (list(exclude_sources), e, CANDIDATES),
    )
    sem = [r[0] for r in cur.fetchall()]

    cur.execute(
        """
        SELECT id FROM kb_vec
        WHERE NOT (source = ANY(%s))
          AND to_tsvector('english', txt) @@ websearch_to_tsquery('english', %s)
        ORDER BY ts_rank_cd(to_tsvector('english', txt), websearch_to_tsquery('english', %s)) DESC
        LIMIT %s
        """,
        (list(exclude_sources), q, q, CANDIDATES),
    )
    lex = [r[0] for r in cur.fetchall()]

    scores = {}
    for ids in (sem, lex):
        for rank, i in enumerate(ids):
            scores[i] = scores.get(i, 0.0) + 1.0 / (RRF_K + rank + 1)
    top = sorted(scores, key=scores.get, reverse=True)[:limit]
    if not top:
        print("[]" if json_output else "No results found.")
        return

    cur.execute("SELECT id, source, path, chunk, txt FROM kb_vec WHERE id = ANY(%s)", (top,))
    rows = {r[0]: r[1:] for r in cur.fetchall()}
    results = []
    for i in top:
        s, p, chunk, t = rows[i]
        t = " ".join(t.split())
        results.append(
            {
                "source": s,
                "path": p,
                "chunk": chunk,
                "text": t[:excerpt_chars],
                "score": round(scores[i], 8),
            }
        )

    if json_output:
        print(json.dumps(results, ensure_ascii=False))
        return

    for result in results:
        print(f"[{result['source']}] {result['path'].split('/')[-1]}: {result['text']}")


def main():
    parser = argparse.ArgumentParser(prog="kb-vec")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("ingest")

    search_parser = sub.add_parser("search")
    search_parser.add_argument("query", nargs="+")
    search_parser.add_argument("--exclude-source", action="append", default=["finance"])
    search_parser.add_argument("--limit", type=int, default=TOPK)
    search_parser.add_argument("--excerpt-chars", type=int, default=EXCERPT)
    search_parser.add_argument("--json", action="store_true", dest="json_output")

    args = parser.parse_args()
    if args.command == "ingest":
        ingest()
        return

    try:
        search(
            " ".join(args.query),
            exclude_sources=args.exclude_source,
            limit=max(1, min(args.limit, 20)),
            excerpt_chars=max(80, min(args.excerpt_chars, 4000)),
            json_output=args.json_output,
        )
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())


if __name__ == "__main__":
    main()
