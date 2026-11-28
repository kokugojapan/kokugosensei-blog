#!/usr/bin/env python3
"""AUTOバックログの自動補充: Claude が出した候補行を機械検査し、通ったものだけを CONTENT-BACKLOG.md に追記する。

使い方: replenish_validate.py <repo> <candidates.txt> <today YYYY-MM-DD> [--max N] [--dry-run]
出力（stdout）: 1行目 "ADDED=<n> REJECTED=<m>"、以降に却下理由（機微なし）。
LLMの判断は使わない。重複判定は既存記事タイトル＋バックログ全タイトルとの文字2-gram Jaccard。
"""
import os
import re
import sys

AUTO_OK = re.compile(r"設問タイプ別|記述深掘り|親向け|学年別")
AUTO_NG = re.compile(r"志望校|塾別|テーマ論|語彙漢字|読書")
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+){1,5}$")
BANNED = re.compile(r"水上|合格|実績|偏差値[0-9０-９]|[0-9０-９]+%|，|．|\*\*|http|サピックス|日能研|四谷|早稲アカ|SAPIX|開成|麻布|桜蔭")
SIM_LIMIT = 0.35   # Jaccard。2026-11-28 の較正: 正当な新テーマの最大0.34、言い換え重複の最小0.37
CONT_LIMIT = 0.65  # 包含率（共通2-gram/短い方）。正当の最大0.58、重複0.72〜0.80
STOP = ("中学受験国語の", "中学受験国語", "中学受験の", "中学受験", "国語の", "国語")


def norm(t):
    t = t.strip().strip("`").strip()
    for s in STOP:
        t = t.replace(s, "")
    return re.sub(r"[\s、。「」『』（）()・,，.．？?！!〜~｜|]", "", t)


def grams(t):
    t = norm(t)
    return {t[i:i + 2] for i in range(len(t) - 1)} or {t}


def sim(a, b):
    ga, gb = grams(a), grams(b)
    return len(ga & gb) / max(1, len(ga | gb))


def cont(a, b):
    ga, gb = grams(a), grams(b)
    return len(ga & gb) / max(1, min(len(ga), len(gb)))


def cells(line):
    parts = line.strip().split("|")
    if len(parts) < 3:
        return None
    return [p.strip() for p in parts[1:-1]]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    mx = 10
    if "--max" in sys.argv:
        mx = int(sys.argv[sys.argv.index("--max") + 1])
        args = [a for a in args if a != str(mx)]
    repo, cand_path, today = args[0], args[1], args[2]
    backlog_path = os.path.join(repo, "CONTENT-BACKLOG.md")
    blog_dir = os.path.join(repo, "src", "content", "blog")

    backlog = open(backlog_path, encoding="utf-8").read()
    titles, slugs, maxno = [], set(), 0
    for line in backlog.splitlines():
        if re.match(r"^\|\s*[0-9]+\s*\|", line):
            c = cells(line)
            if c and len(c) >= 8:
                maxno = max(maxno, int(c[0]))
                titles.append(c[3])
                slugs.add(c[4].strip("`").strip())
    for f in os.listdir(blog_dir):
        if f.endswith(".md"):
            slugs.add(f[:-3])
            with open(os.path.join(blog_dir, f), encoding="utf-8") as fh:
                for ln in fh:
                    if ln.startswith("title:"):
                        titles.append(ln[6:].strip().strip('"'))
                        break

    added, rejected = [], []
    for raw in open(cand_path, encoding="utf-8").read().splitlines():
        if not raw.strip().startswith("|"):
            continue
        c = cells(raw)
        if not c or len(c) != 5:
            rejected.append("列数不正")
            continue
        title, slug, kw, cluster, angle = c
        slug = slug.strip("`").strip()
        why = None
        if not SLUG_RE.match(slug) or len(slug) > 50:
            why = "slug形式"
        elif slug in slugs:
            why = f"slug重複({slug})"
        elif not AUTO_OK.search(cluster) or AUTO_NG.search(cluster):
            why = f"クラスタ対象外({slug})"
        elif not (12 <= len(title) <= 50):
            why = f"タイトル長({slug})"
        elif not (60 <= len(angle) <= 220):
            why = f"切り口の長さ({slug})"
        elif "国語" not in kw or len(kw) > 40:
            why = f"狙いKW({slug})"
        elif BANNED.search(title + kw + angle):
            why = f"禁止表現({slug})"
        else:
            best = max((sim(title, t) for t in titles), default=0)
            bc = max((cont(title, t) for t in titles), default=0)
            if best >= SIM_LIMIT or bc >= CONT_LIMIT:
                why = f"既存と類似J{best:.2f}/C{bc:.2f}({slug})"
        if why:
            rejected.append(why)
            continue
        if len(added) >= mx:
            rejected.append(f"上限超過({slug})")
            continue
        maxno += 1
        added.append(f"| {maxno} | should | 未調査 | {title} | `{slug}` | {kw} | {cluster} | {angle} |")
        titles.append(title)
        slugs.add(slug)

    if added and not dry:
        block = (
            f"\n## 自動補充（{today}）\n\n"
            "run.sh の replenish が生成し、replenish_validate.py の機械検査（slug・クラスタ・禁止表現・既存タイトルとの類似度）を通った行。\n\n"
            "| # | 優先 | 需要 | タイトル | slug | 狙いKW | クラスタ | 独自の切り口 |\n"
            "|---|---|---|---|---|---|---|---|\n" + "\n".join(added) + "\n"
        )
        with open(backlog_path, "a", encoding="utf-8") as fh:
            if not backlog.endswith("\n"):
                fh.write("\n")
            fh.write(block)
    print(f"ADDED={len(added)} REJECTED={len(rejected)}")
    for r in rejected:
        print(r)


if __name__ == "__main__":
    main()
