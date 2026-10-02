"""Base de connaissance (RAG) du projet : docs/kb/*.md -> passages indexés, recherche BM25 sans dépendance.

  python3 tools/kb.py build                # (re)construit docs/kb/index.jsonl
  python3 tools/kb.py search "trottoir collision" [-k 4]   # meilleurs passages, prêts à coller dans un prompt
"""
import json, math, os, re, sys, unicodedata

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
KB = os.path.join(ROOT, "docs", "kb")
INDEX = os.path.join(KB, "index.jsonl")
STOP = set("le la les de des du un une et ou en au aux a à d l pour par sur dans est sont the of to with que qui ne pas plus".split())


def norm(t):
    t = unicodedata.normalize("NFD", t.lower())
    return "".join(c for c in t if unicodedata.category(c) != "Mn")


def tokens(t):
    return [w for w in re.findall(r"[a-z0-9_.]+", norm(t)) if w not in STOP and len(w) > 1]


def parse(path):
    s = open(path, encoding="utf-8").read()
    meta, body = {}, s
    m = re.match(r"---\n(.*?)\n---\n(.*)", s, re.S)
    if m:
        body = m.group(2)
        for line in m.group(1).splitlines():
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()
    return meta, body


def chunks(meta, body, size=900):
    """Découpe par sections (#) puis par paragraphes, ~900 caractères, avec le titre de la fiche en contexte."""
    parts, cur = [], ""
    for block in re.split(r"\n(?=#)|\n\n", body):
        if len(cur) + len(block) > size and cur:
            parts.append(cur.strip()); cur = ""
        cur += block + "\n\n"
    if cur.strip():
        parts.append(cur.strip())
    return parts


def build():
    n = 0
    with open(INDEX, "w", encoding="utf-8") as out:
        for f in sorted(os.listdir(KB)):
            if not f.endswith(".md"):
                continue
            meta, body = parse(os.path.join(KB, f))
            for k, text in enumerate(chunks(meta, body)):
                rec = dict(id="%s#%d" % (meta.get("id", f), k), fiche=f, titre=meta.get("titre", ""),
                           tags=meta.get("tags", ""), sources=meta.get("sources", ""), texte=text)
                out.write(json.dumps(rec, ensure_ascii=False) + "\n"); n += 1
    print(n, "passages ->", os.path.relpath(INDEX, ROOT))


def search(q, k=4):
    if not os.path.exists(INDEX):
        build()
    docs = [json.loads(l) for l in open(INDEX, encoding="utf-8")]
    toks = [tokens(d["texte"]) for d in docs]
    N = len(docs); avg = sum(map(len, toks)) / max(N, 1)
    df = {}
    for t in toks:
        for w in set(t):
            df[w] = df.get(w, 0) + 1
    qt = tokens(q)
    scores = []
    for d, t in zip(docs, toks):
        tf = {}
        for w in t:
            tf[w] = tf.get(w, 0) + 1
        s = 0.0
        for w in qt:
            # préfixes : « trottoir » trouve « trottoirs »
            f = sum(c for x, c in tf.items() if x.startswith(w) or (w.startswith(x) and len(x) > 3))
            if f:
                idf = math.log(1 + (N - df.get(w, 0) + 0.5) / (df.get(w, 0) + 0.5))
                s += idf * f * 2.2 / (f + 1.2 * (0.25 + 0.75 * len(t) / avg))
        # bonus si le mot figure dans le titre ou les étiquettes de la fiche
        head = tokens(d["titre"] + " " + d["tags"])
        for w in qt:
            if any(x.startswith(w) or (w.startswith(x) and len(x) > 3) for x in head):
                s += 1.6 * math.log(1 + (N - df.get(w, 0) + 0.5) / (df.get(w, 0) + 0.5))
        scores.append(s)
    best = sorted(range(N), key=lambda i: -scores[i])[:k]
    for i in best:
        if scores[i] <= 0:
            continue
        d = docs[i]
        print("### %s — %s (score %.1f, sources : %s)\n%s\n" % (d["id"], d["titre"], scores[i], d["sources"], d["texte"]))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "build":
        build()
    elif len(sys.argv) > 2 and sys.argv[1] == "search":
        k = int(sys.argv[sys.argv.index("-k") + 1]) if "-k" in sys.argv else 4
        search(" ".join(a for a in sys.argv[2:] if a != "-k" and not a.isdigit()), k)
    else:
        print(__doc__)
