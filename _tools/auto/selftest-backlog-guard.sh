#!/bin/bash
# run.sh の「AUTOバックログ残数（META・残り7本以下の通知）」と「当日公開済みなら何もしない」を、
# 一時ディレクトリの偽repo・偽通知で run.sh を実際に流して確かめる。selftest.sh から呼ぶ。単独でも実行できる。
# 本物の state・ログ・Slack・Claude には触れない（HOME も一時ディレクトリ）。どの回も生成の手前
# （sandbox部品の検査）で止まるので、Claude も push も呼ばれない。
set -euo pipefail

RUNNER="$(cd "$(dirname "$0")" && pwd)/run.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/kokugo-blog-guard-selftest.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail() { echo "SELFTEST_FAIL backlog-guard: $*" >&2; exit 1; }
TODAY=$(TZ=Asia/Tokyo date '+%Y-%m-%d')
YESTERDAY=$(TZ=Asia/Tokyo date -d "$TODAY -1 days" '+%Y-%m-%d' 2>/dev/null \
  || TZ=Asia/Tokyo date -j -v-1d -f '%Y-%m-%d' "$TODAY" '+%Y-%m-%d')
LOG="$T/logs/kokugo-blog-auto.log"
PUB="$T/logs/kokugo-blog-auto.published.log"
STAMP="$T/state/backlog-low-notified"

# 偽の通知2本（呼ばれた引数を記録するだけ）。claude・codex・sandbox部品は置かない。
mkdir -p "$T/home/.local/bin" "$T/sandbox-empty" "$T/state" "$T/logs"
for n in notify-slack notify-failure; do
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/%s.calls"\n' "$T" "$n" > "$T/home/.local/bin/$n.sh"
  chmod +x "$T/home/.local/bin/$n.sh"
done
: > "$T/notify-slack.calls"
: > "$T/notify-failure.calls"

# 偽repo: AUTO候補 t01..tN と対象外（志望校別）1本。t01 は公開済みファイル、t02 は done 台帳にある。
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/repo" 2>/dev/null
G() { git -C "$T/repo" -c user.email=selftest@example.invalid -c user.name=selftest "$@"; }
backlog() {  # backlog <AUTO候補の本数>
  {
    echo '| # | 優先 | 難度 | タイトル | slug | KW | クラスタ | 切り口 |'
    echo '|---|---|---|---|---|---|---|---|'
    echo '| 1 | must | high | 対象外 | `x01` | kw | 志望校別 | a |'
    for i in $(seq 1 "$1"); do
      printf '| %d | should | medium | 題%02d | `t%02d` | kw | 設問タイプ別（選択肢） | a |\n' "$((i + 1))" "$i" "$i"
    done
  } > "$T/repo/CONTENT-BACKLOG.md"
  G add CONTENT-BACKLOG.md
  G commit -qm "backlog $1"
  G push -q origin HEAD 2>/dev/null
}
mkdir -p "$T/repo/src/content/blog" "$T/repo/_tools/auto"
printf 'published\n' > "$T/repo/src/content/blog/t01.md"
printf 'slug=__SLUG__\n' > "$T/repo/_tools/auto/prompt.tmpl.md"
G add src/content/blog/t01.md _tools/auto/prompt.tmpl.md
backlog 6
G push -q -u origin HEAD 2>/dev/null
printf 't02\n' > "$T/state/done.txt"

run() {  # run [VAR=値 ...]  呼出し元の環境変数（DRY_RUN・*_BIN など）は持ち込まない
  env -i PATH="$PATH" HOME="$T/home" TMPDIR="$T" \
    KOKUGO_BLOG_REPO="$T/repo" KOKUGO_BLOG_STATE="$T/state" KOKUGO_BLOG_LOGDIR="$T/logs" \
    CLAUDE_BIN="$T/no-claude" CLAUDE_SANDBOX_BIN="$T/sandbox-empty" "$@" bash "$RUNNER" \
    || fail "run.sh rc=$?"
  [ ! -e "$T/state/lock" ] || fail "lock left behind"
  ! grep -q 'WARN: claude exited\|公開成功' "$LOG" || fail "reached generation or publish"
}
calls() { wc -l < "$T/notify-slack.calls" | tr -d ' '; }
md() { printf '%s\n' "$1" | awk -F- '{print $2+0 "/" $3+0}'; }
after() { TZ=Asia/Tokyo date -d "$TODAY $1 days" '+%Y-%m-%d' 2>/dev/null \
  || TZ=Asia/Tokyo date -j -v+"$1"d -f '%Y-%m-%d' "$TODAY" '+%Y-%m-%d'; }

# 1) 残り3本（t03 を選び t04..t06 が残る）: META に残数と枯渇日、Slack に1通。生成の手前で止まる。
run
exhaust=$(after 4)
grep -qF "KOKUGO_BLOG_META status=selected slug=t03 remaining=3 exhaust=$exhaust" "$LOG" || fail "META remaining=3"
[ "$(calls)" -eq 1 ] || fail "low-backlog notice must be sent once"
grep -qF "残り3本（$(md "$exhaust") に枯渇）" "$T/notify-slack.calls" || fail "notice text"
grep -q 'Claude sandbox dependency missing' "$LOG" || fail "must stop before generation"
[ -s "$STAMP" ] || fail "notice stamp missing"

# 2) 12時間以内の再実行では送らない。12時間たてば継続中として再送する。
run
[ "$(calls)" -eq 1 ] || fail "notice must be throttled within 12h"
echo $(( $(date +%s) - 43200 )) > "$STAMP"
run
[ "$(calls)" -eq 2 ] || fail "notice must repeat after 12h"

# 3) 残り8本（補充後）: 通知せず、印を消す（次に減ったらすぐ知らせる）。
backlog 11
run
grep -qF "KOKUGO_BLOG_META status=selected slug=t03 remaining=8 exhaust=$(after 9)" "$LOG" || fail "META remaining=8"
[ "$(calls)" -eq 2 ] || fail "no notice when remaining > 7"
[ ! -e "$STAMP" ] || fail "stamp must be cleared when remaining > 7"
backlog 6

# 4) PUB_LOG に今日の行: 記録して exit 0。選定・通知・失敗通知のどれにも進まない。
printf -- '- %s  題  https://blog.kokugosensei.com/blog/x/  (2500字)\n' "$YESTERDAY" > "$PUB"
printf -- '- %s  題  https://blog.kokugosensei.com/blog/t00/  (2500字)\n' "$TODAY" >> "$PUB"
: > "$LOG"
fails_before=$(wc -l < "$T/notify-failure.calls")
run
grep -qF "already published today ($TODAY), skip." "$LOG" || fail "already-published line"
grep -q 'KOKUGO_BLOG_META status=skipped_published_today' "$LOG" || fail "already-published META"
! grep -q 'status=selected\|start (' "$LOG" || fail "must exit before selection"
[ "$(calls)" -eq 2 ] || fail "no Slack when already published"
[ "$(wc -l < "$T/notify-failure.calls")" -eq "$fails_before" ] || fail "no failure notice when already published"

# 5) DRY_RUN は公開しないのでガードの対象外。ただし残数通知は送らない。
: > "$LOG"
run DRY_RUN=1
grep -q 'KOKUGO_BLOG_META status=selected slug=t03 remaining=3' "$LOG" || fail "DRY_RUN must pass the guard"
[ "$(calls)" -eq 2 ] || fail "no notice in DRY_RUN"

# 6) 前日の行だけなら通常どおり選定へ進む。
printf -- '- %s  題  https://blog.kokugosensei.com/blog/x/  (2500字)\n' "$YESTERDAY" > "$PUB"
: > "$LOG"
run
grep -q 'KOKUGO_BLOG_META status=selected slug=t03 remaining=3' "$LOG" || fail "yesterday's line must not block"
[ "$(calls)" -eq 3 ] || fail "first notice after stamp cleared"

echo "SELFTEST_OK backlog-guard"
