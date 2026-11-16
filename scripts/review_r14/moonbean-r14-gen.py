#!/usr/bin/env python3
"""Generate seed list + mutated variants for MoonBean r14 differential review."""
import glob, json, os, random, sys

REPO = "/tmp/r14"
OUT = "/tmp/r14-review/mut"
random.seed(1415)
os.makedirs(OUT, exist_ok=True)

seeds = []
for pat in ["tests/ledgers/*.beancount", "tests/r9/**/*.beancount", "tests/r10/**/*.beancount",
            "tests/r11/**/*.beancount", "tests/r12/**/*.beancount", "tests/r13/**/*.beancount",
            "tests/r14/**/*.beancount", "examples/*.beancount", "examples/**/*.beancount"]:
    for p in sorted(glob.glob(os.path.join(REPO, pat), recursive=True)):
        if p not in seeds:
            seeds.append(p)

gen = []

def w(name, data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    p = os.path.join(OUT, name + ".beancount")
    with open(p, "wb") as f:
        f.write(data)
    gen.append(p)

# authored parser cases from the candidate repo (sources only)
for i, c in enumerate(json.load(open(os.path.join(REPO, "tests/r14/parser-cases.json")))):
    if "source" in c:
        w(f"pc{i:02d}-{c['name']}", c["source"])

# generic mutations over a sample of seeds (skip huge files)
small = [s for s in seeds if os.path.getsize(s) < 60000 and "/tests/r14/" not in s]
sample = random.sample(small, 28)
for k, s in enumerate(sample):
    b = open(s, "rb").read()
    t = b.decode("utf-8", "replace")
    base = f"g{k:02d}-" + os.path.basename(s).replace(".beancount", "")
    w(base + ".crlf", t.replace("\r\n", "\n").replace("\n", "\r\n"))
    w(base + ".bom", b"\xef\xbb\xbf" + b)
    w(base + ".tabs", "\n".join(("\t" + l[2:]) if l.startswith("  ") else l for l in t.split("\n")))
    w(base + ".nonl", t.rstrip("\n"))
    cut = random.randint(1, max(1, len(b) - 1))
    w(base + ".trunc", b[:cut])
    lines = t.split("\n")
    qi = [i for i, l in enumerate(lines) if '"' in l]
    if qi:
        i = random.choice(qi)
        j = lines[i].rfind('"')
        l2 = lines[:]; l2[i] = lines[i][:j] + lines[i][j + 1:]   # drop a closing quote
        w(base + ".unterm", "\n".join(l2))
        l3 = lines[:]; l3[i] = lines[i].replace('"', '"Ünïcødé ☃ 日本 ', 1)
        w(base + ".uni", "\n".join(l3))
        l4 = lines[:]; l4[i] = lines[i].replace('"', '"' + "L" * 9000, 1)
        w(base + ".long", "\n".join(l4))

H = "2024-01-01 open Assets:A USD,EUR\n2024-01-01 open Equity:E\n"
TX = '2024-01-02 * "payee" "narr"\n  Assets:A 1 USD\n  Equity:E\n'

def txmeta(m):
    return H + f'2024-01-02 * "p" "n"\n  {m}\n  Assets:A 1 USD\n  Equity:E\n'

# multi-line strings
ml = {
    "ml-narr": H + '2024-01-02 * "line1\nline2"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-blank": H + '2024-01-02 * "line1\n\n\nline4"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-indent": H + '2024-01-02 * "a\n    indented\n\tt"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-escq": H + '2024-01-02 * "a \\"q\\"\nb \\\\ c"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-crlf": (H + '2024-01-02 * "a\r\nb"\n  Assets:A 1 USD\n  Equity:E\n'),
    "ml-crlf-all": (H + '2024-01-02 * "a\nb"\n  Assets:A 1 USD\n  Equity:E\n').replace("\n", "\r\n"),
    "ml-payee-narr": H + '2024-01-02 * "p\nq" "n\nm"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-meta": txmeta('memo: "x\ny"'),
    "ml-meta-blank": txmeta('memo: "x\n\ny"'),
    "ml-postmeta": H + '2024-01-02 * "p"\n  Assets:A 1 USD\n    memo: "a\nb"\n  Equity:E\n',
    "ml-note": H + '2024-01-03 note Assets:A "n1\nn2"\n',
    "ml-event": H + '2024-01-03 event "loc" "a\nb"\n',
    "ml-query": H + '2024-01-03 query "q" "SELECT\n  account"\n',
    "ml-custom": H + '2024-01-03 custom "budget" "a\nb" 10 USD\n',
    "ml-option": 'option "title" "T1\nT2"\n' + H,
    "ml-open-meta": "2024-01-01 open Assets:A\n  d: \"x\ny\"\n",
    "ml-tail-text": H + '2024-01-02 * "a\nb\n2024-01-05 * \\"looks\\" like tx"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-looks-like-dir": H + '2024-01-02 * "a\n2024-01-03 open Assets:B\n"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-unicode": H + '2024-01-02 * "日本\n☃"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-backslash-nl": H + '2024-01-02 * "a\\\nb"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-empty-lines-only": H + '2024-01-02 * "\n\n"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-trailing-ws": H + '2024-01-02 * "a   \n   b  "\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-tag-after": H + '2024-01-02 * "a\nb" #tag ^link\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-long": H + '2024-01-02 * "' + "\n".join("x" * 50 for _ in range(300)) + '"\n  Assets:A 1 USD\n  Equity:E\n',
    "ml-balance-after": H + '2024-01-02 * "a\nb"\n  Assets:A 1 USD\n  Equity:E\n2024-01-03 balance Assets:A 1 USD\n',
    "ml-bad-balance-line": H + '2024-01-02 * "a\nb"\n  Assets:A 1 USD\n  Equity:E\n2024-01-03 balance Assets:A 2 USD\n',
    "ml-pushtag": 'pushtag #t\n' + H + '2024-01-02 * "a\nb"\n  Assets:A 1 USD\n  Equity:E\npoptag #t\n',
    "ml-pushmeta": 'pushmeta who: "x\ny"\n' + H + TX + 'popmeta who:\n',
    "ml-cr-only": (H + '2024-01-02 * "a\rb"\n  Assets:A 1 USD\n  Equity:E\n'),
    "ml-nul": (H + '2024-01-02 * "a\x00b"\n  Assets:A 1 USD\n  Equity:E\n'),
}
for k, v in ml.items():
    w(k, v)
    w(k + ".bom", b"\xef\xbb\xbf" + v.encode())
    w(k + ".nonl", v.rstrip("\n"))

# unterminated strings at various positions
un = {
    "un-narr-eof": H + '2024-01-02 * "abc',
    "un-narr-nl-eof": H + '2024-01-02 * "abc\n',
    "un-narr-mid": H + '2024-01-02 * "abc\n  Assets:A 1 USD\n  Equity:E\n' + TX,
    "un-payee": H + '2024-01-02 * "p "n\n  Assets:A 1 USD\n  Equity:E\n',
    "un-meta": txmeta('memo: "x'),
    "un-meta-last": H + TX + '2024-01-03 note Assets:A "n\n',
    "un-open-meta": '2024-01-01 open Assets:A\n  d: "x\n' + TX,
    "un-option": 'option "title "T\n' + H + TX,
    "un-include": 'include "x.beancount\n' + H + TX,
    "un-postmeta": H + '2024-01-02 * "p"\n  Assets:A 1 USD\n    memo: "a\n  Equity:E\n',
    "un-closes-later": H + '2024-01-02 * "abc\n  Assets:A 1 USD\n  Equity:E\n2024-01-03 * "x"\n  Assets:A 1 USD\n  Equity:E\n',
    "un-odd-quotes": H + '2024-01-02 * "a" "b\n  Assets:A 1 USD\n  Equity:E\n' + TX + TX,
    "un-escaped-end": H + '2024-01-02 * "abc\\"\n  Assets:A 1 USD\n  Equity:E\n',
    "un-only": '"',
    "un-comment-quote": H + '; "unterminated in comment\n' + TX,
    "un-after-comment": H + '2024-01-02 * "a" ; "c\n  Assets:A 1 USD\n  Equity:E\n',
    "un-event": H + '2024-01-03 event "loc "a\n' + TX,
    "un-custom": H + '2024-01-03 custom "b "a\n' + TX,
    "un-price": H + '2024-01-03 price USD 1 EUR\n2024-01-03 note Assets:A "\n' + TX,
    "un-crlf": (H + '2024-01-02 * "abc\n  Assets:A 1 USD\n  Equity:E\n' + TX).replace("\n", "\r\n"),
}
for k, v in un.items():
    w(k, v)

# metadata values
metas = ["kk: 10 USD", "kk: -10.50 EUR", "kk: 1,000.00 USD", "kk: (1+2) USD", "kk: 2*3 USD", "kk: -1 USD",
         "kk: 10.", "kk: .5 USD", "kk: 10 usd", "kk: USD", "kk: 10", "kk: -3.25", "kk: 2024-01-01",
         "kk: TRUE", "kk: FALSE", "kk: Assets:A", "kk: #tag", "kk: ^link", "kk:", "kk: NULL",
         "kk: 10 USD EUR", "kk: 10 USD ; c", "kk: 1e3 USD", "kk: 10 USD {5 EUR}", "kk: +5 USD",
         "kk: 10  USD", "kk:\t10\tUSD", "kk: 10 VERYLONGCURRENCYNAMEXYZ", "kk: 10 A'B", "kk: 10 X.Y_Z-1",
         "kk: 1 / 3 USD", "kk: (1) USD", "kk: 0 USD", "kk: -0.00 USD", "kk: 123456789012345678901234567890.123 USD",
         "k-1: 5 USD", "kA_b: 5 USD", "kk: 5 USD\n  kk: 6 USD"]
for i, m in enumerate(metas):
    w(f"meta{i:02d}-tx", txmeta(m))
    w(f"meta{i:02d}-post", H + f'2024-01-02 * "p"\n  Assets:A 1 USD\n    {m}\n  Equity:E\n')
    w(f"meta{i:02d}-open", f"2024-01-01 open Assets:A\n  {m}\n2024-01-01 open Equity:E\n" + TX.replace(" USD", ""))
w("meta-push-amount", "pushmeta kk: 10 USD\n" + H + TX + "popmeta kk:\n")
w("meta-push-empty", "pushmeta kk:\n" + H + TX + "popmeta kk:\n")
w("meta-amount-crlf", txmeta("kk: 10 USD").replace("\n", "\r\n"))
w("meta-amount-bal", H + TX + '2024-01-03 balance Assets:A 1 USD\n  kk: -2 EUR\n')
w("meta-amount-price", H + '2024-01-03 price EUR 1.1 USD\n  kk: 3 USD\n')

# document directives
D = "/tmp/r14-review/mut"
os.makedirs(os.path.join(D, "docs/sub"), exist_ok=True)
for f in ["exists.pdf", "docs/a.pdf", "docs/sub/b.pdf", "sp ace.pdf", "ünï.pdf"]:
    open(os.path.join(D, f), "w").write("x")
docs = {
    "doc-exist": '"exists.pdf"', "doc-missing": '"missing.pdf"', "doc-rel-sub": '"docs/a.pdf"',
    "doc-rel-dot": '"./exists.pdf"', "doc-rel-up": '"../mut/exists.pdf"', "doc-up-missing": '"../nope/exists.pdf"',
    "doc-abs": f'"{D}/exists.pdf"', "doc-abs-missing": f'"{D}/nope.pdf"', "doc-dir": '"docs"',
    "doc-dir-slash": '"docs/"', "doc-space": '"sp ace.pdf"', "doc-unicode": '"ünï.pdf"',
    "doc-tilde": '"~/nope-r14.pdf"', "doc-empty": '""', "doc-dotdot-chain": '"docs/sub/../a.pdf"',
    "doc-double-slash": '"docs//a.pdf"', "doc-esc-quote": '"a\\"b.pdf"', "doc-ml": '"exists\n.pdf"',
}
for k, v in docs.items():
    w(k, H + f"2024-01-05 document Assets:A {v}\n")
w("doc-tag-link", H + '2024-01-05 document Assets:A "exists.pdf" #t ^l\n')
w("doc-two", H + '2024-01-05 document Assets:A "exists.pdf"\n2024-01-06 document Assets:A "missing2.pdf"\n')
w("doc-closed-acct", H + '2024-01-03 close Assets:A\n2024-01-05 document Assets:A "exists.pdf"\n')
w("doc-unknown-acct", H + '2024-01-05 document Assets:Zzz "exists.pdf"\n')
w("doc-crlf", (H + '2024-01-05 document Assets:A "missing.pdf"\n').replace("\n", "\r\n"))
# include: document in included file is relative to the included file
open(os.path.join(D, "docs/inc.beancount_"), "w").write('2024-01-05 document Assets:A "sub/b.pdf"\n')
open(os.path.join(D, "docs/inc-miss.beancount_"), "w").write('2024-01-05 document Assets:A "exists.pdf"\n')
w("doc-include-rel", H + 'include "docs/inc.beancount_"\n')
w("doc-include-miss", H + 'include "docs/inc-miss.beancount_"\n')
w("doc-option-documents", 'option "documents" "docs"\n' + H + '2024-01-05 document Assets:A "a.pdf"\n')

json.dump({"seeds": seeds, "generated": gen}, open("/tmp/r14-review/inputs.json", "w"), indent=0)
print(len(seeds), "seeds;", len(gen), "generated")
