import os, sys, time, json, glob, urllib.request, hashlib
import psycopg2
EMBED="http://127.0.0.1:18200/v1/embeddings"
PG=dict(host="127.0.0.1",port=5432,dbname="cognee",user="cognee",password="cognee")
def embed(texts):
    body=json.dumps({"input":texts,"model":"qwen3-embedding-0.6b"}).encode()
    r=urllib.request.urlopen(urllib.request.Request(EMBED,body,{"Content-Type":"application/json"}),timeout=60)
    return [d["embedding"] for d in json.load(r)["data"]]
def chunks(t,n=1500):
    t=t.strip(); return [t[i:i+n] for i in range(0,len(t),n)] or [""]
def ingest():
    con=psycopg2.connect(**PG); cur=con.cursor()
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
    cur.execute("CREATE TABLE IF NOT EXISTS kb_vec(id bigserial primary key, source text, path text, chunk int, txt text, emb vector(1024))")
    cur.execute("TRUNCATE kb_vec"); con.commit()
    files=glob.glob("/var/lib/kb/staging/**/*.md",recursive=True)
    t0=time.time(); n=0; batch=[]; meta=[]
    def flush():
        nonlocal n
        if not batch: return
        embs=embed(batch)
        for (src,path,ci,txt),e in zip(meta,embs):
            cur.execute("INSERT INTO kb_vec(source,path,chunk,txt,emb) VALUES(%s,%s,%s,%s,%s)",(src,path,ci,txt,str(e)))
            n+=1
        con.commit(); batch.clear(); meta.clear()
    for f in files:
        src=f.split("/var/lib/kb/staging/")[-1].split("/")[0]; txt=open(f,errors="ignore").read()
        for ci,c in enumerate(chunks(txt)):
            batch.append(c); meta.append((src,f,ci,c))
            if len(batch)>=32: flush()
    flush()
    cur.execute("CREATE INDEX IF NOT EXISTS kb_vec_idx ON kb_vec USING ivfflat (emb vector_cosine_ops)")
    con.commit()
    print(f"INDEXED {n} chunks from {len(files)} docs in {time.time()-t0:.1f}s")
def search(q):
    con=psycopg2.connect(**PG); cur=con.cursor()
    e=embed([q])[0]
    cur.execute("SELECT source,path,left(txt,160) FROM kb_vec ORDER BY emb <=> %s LIMIT 5",(str(e),))
    for s,p,t in cur.fetchall(): print(f"[{s}] {p.split('/')[-1]}: {t.strip()[:140]}")
if sys.argv[1]=="ingest": ingest()
else: search(" ".join(sys.argv[2:]))
