#!/bin/bash
# 中受国語ブログ 記事自動生成＋公開 — VPS systemd kokugo-blog-auto.timer から毎日発火。
# CONTENT-BACKLOG.md の未生成の最上位（AUTO=method系クラスタのみ）を1本 Claude で生成し、
# 安全ガードを通ったものだけ git commit+push して自動公開する（GitHub Actions が blog.kokugosensei.com へデプロイ）。
# 独自資産系（志望校別・塾別・テーマ論・語彙漢字・読書）はこのジョブでは扱わない（対話で人間レビュー）。
#
# 設計方針: git操作は全てこのシェルが行う。Claude はBash/Web/MCPなしで本文だけを保存し、
#   シェルはstdoutの KOKUGO_BLOG_META 行（機微なし）だけをログに残す。ガード不通過は _drafts/ へ隔離し公開しない。
#   ~/.local/state/kokugo-blog-auto/disabled があれば何もしない（キルスイッチ）。DRY_RUN=1 で push せずテスト。

# UTF-8ロケールを固定。launchd/非対話は既定Cロケールになり、wc -m がバイト数を数え、
# awk/sed が日本語(multibyte)を壊す（文字数ガード誤判定・ログ文字化けの原因）。
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# macOS（Mac本体）とLinux（ConoHa VPS）の両方で動くようにパスは $HOME 基準にする。
# 環境変数で個別に上書きも可能（テスト時や配置換えのため）。
REPO="${KOKUGO_BLOG_REPO:-$HOME/dev/kokugosensei-blog}"
STATE_DIR="${KOKUGO_BLOG_STATE:-$HOME/.local/state/kokugo-blog-auto}"
# ログ置き場はOSで分ける（macOSは~/Library/Logs、Linuxにはその慣習がない）
if [ "$(uname -s)" = "Darwin" ]; then
  LOG_DIR="${KOKUGO_BLOG_LOGDIR:-$HOME/Library/Logs/automation}"
else
  LOG_DIR="${KOKUGO_BLOG_LOGDIR:-$HOME/.local/state/logs/automation}"
fi
LOCK="$STATE_DIR/lock"
DONE="$STATE_DIR/done.txt"
LOG_FILE="$LOG_DIR/kokugo-blog-auto.log"
ERR_LOG="$LOG_DIR/kokugo-blog-auto.err.log"
PUB_LOG="$LOG_DIR/kokugo-blog-auto.published.log"
CLAUDE="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-sonnet-5}"
CLAUDE_SANDBOX_BIN="${CLAUDE_SANDBOX_BIN:-$STATE_DIR/sandbox-bin}"
EXPECTED_BWRAP_SHA256="77360cb751ccedc5971391444ac86a8a33c15b04d6b4a6fe45f5d25496e62c4c"
EXPECTED_SOCAT_SHA256="4ba71cb9e75952234ca0f3af74db33ba017d6d8c66b1ccd323e80aa9bd80f0a9"
NOTIFY_FAIL="$HOME/.local/bin/notify-failure.sh"
TN="/opt/homebrew/bin/terminal-notifier"          # macOSのみ
NOTIFY_SLACK="$HOME/.local/bin/notify-slack.sh"   # VPS側のバナー代替
# タイムアウト: macOSはcoreutilsのgtimeout、Linuxは標準のtimeout
GTIMEOUT=$(command -v gtimeout 2>/dev/null || command -v timeout 2>/dev/null || true)
TMPL="$REPO/_tools/auto/prompt.tmpl.md"
JOB="kokugo-blog-auto"
TS() { TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'; }
TODAY=$(TZ=Asia/Tokyo date '+%Y-%m-%d')

mkdir -p "$STATE_DIR" "$LOG_DIR"
touch "$DONE"

log() { echo "[$(TS)] $*" >> "$LOG_FILE"; }
# 通知: macOSはバナー、VPSはSlack。どちらも不在ならログのみ（ジョブは止めない）
banner() {
  if [ -x "$TN" ]; then
    "$TN" -title "$1" -message "$2" -sound "${3:-Glass}" >/dev/null 2>&1 || true
  elif [ -x "$NOTIFY_SLACK" ]; then
    "$NOTIFY_SLACK" "$1" "$2" >/dev/null 2>&1 || true
  fi
}
# Claudeには記事作成に必要なネイティブのファイルツールだけを渡す。
# シェル・ネットワーク・MCP・サブエージェントは露出せず、権限確認が必要な操作はdontAskで拒否する。
run_claude() {
  local prompt="$1"
  local settings='{"permissions":{"disableBypassPermissionsMode":"disable","deny":["Bash","WebFetch","WebSearch","Agent","Task"]},"sandbox":{"enabled":true,"failIfUnavailable":true,"allowUnsandboxedCommands":false,"network":{"allowedDomains":[]}}}'
  local args=(-p "$prompt" --model "$CLAUDE_MODEL" --permission-mode dontAsk
    --tools "Read,Write,Edit,Glob,Grep" --allowedTools "Read,Write,Edit,Glob,Grep"
    --settings "$settings" --strict-mcp-config --mcp-config '{"mcpServers":{}}'
    --disable-slash-commands --no-chrome --no-session-persistence --safe-mode --output-format text)
  if [ -n "$GTIMEOUT" ]; then
    env PATH="$CLAUDE_SANDBOX_BIN:$PATH" "$GTIMEOUT" 1200 "$CLAUDE" "${args[@]}"
  else
    env PATH="$CLAUDE_SANDBOX_BIN:$PATH" "$CLAUDE" "${args[@]}"
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

check_sandbox_dependency() {
  local name="$1" expected="$2" path="$CLAUDE_SANDBOX_BIN/$1"
  if [ ! -x "$path" ]; then
    log "Claude sandbox dependency missing: $path"
    "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "missing sandbox dependency: $name"
    return 1
  fi
  if [ "$(sha256_file "$path")" != "$expected" ]; then
    log "Claude sandbox dependency checksum mismatch: $path"
    "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "sandbox dependency checksum mismatch: $name"
    return 1
  fi
}

# キルスイッチ
if [ -f "$STATE_DIR/disabled" ]; then log "disabled, skip."; exit 0; fi

# 多重起動防止
if ! mkdir "$LOCK" 2>/dev/null; then log "already running, skip."; exit 0; fi
trap 'rc=$?; rmdir "$LOCK" 2>/dev/null; [ "$rc" -eq 0 ] || "$NOTIFY_FAIL" "'"$JOB"'" "$rc" "'"$ERR_LOG"'"' EXIT

log "start ($TODAY)"
cd "$REPO" || { log "cd failed"; exit 1; }

# リポジトリを最新化（人間のpushと衝突しないよう）。ff-onlyで安全に。失敗したら中断（無理に進めない）。
if ! git pull --ff-only --quiet 2>>"$ERR_LOG"; then
  log "git pull --ff-only 失敗（diverge/衝突の可能性）。中断。"
  "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "git pull failed"
  exit 0
fi

# Claude に渡す前の作業ツリーはclean必須。既存変更をAI生成と混ぜない。
if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
  log "作業ツリーがcleanではないため中断。"
  "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "working tree is not clean"
  exit 0
fi

# ---- 次に書く記事を選定（AUTO=method系クラスタのみ・rank順・既存/done除外） ----
CAND=$(awk -F'|' '
  /^\| *[0-9]+ *\|/ {
    rank=$2; gsub(/ /,"",rank);
    title=$5; gsub(/^[[:space:]]+|[[:space:]]+$/,"",title);
    slug=$6; gsub(/[`[:space:]]/,"",slug);
    kw=$7; gsub(/^[[:space:]]+|[[:space:]]+$/,"",kw);
    cl=$8; gsub(/^[[:space:]]+|[[:space:]]+$/,"",cl);
    if (cl ~ /設問タイプ別|記述深掘り|親向け|学年別/ && cl !~ /志望校|塾別|テーマ論|語彙漢字|読書/) {
      print rank "\t" slug "\t" title "\t" kw "\t" cl
    }
  }
' CONTENT-BACKLOG.md)

SLUG=""; TITLE=""; KW=""; CLUSTER=""
while IFS=$'\t' read -r r s t k c; do
  [ -z "$s" ] && continue
  [ -f "src/content/blog/$s.md" ] && continue
  grep -qxF "$s" "$DONE" 2>/dev/null && continue
  SLUG="$s"; TITLE="$t"; KW="$k"; CLUSTER="$c"; break
done <<< "$CAND"

if [ -z "$SLUG" ]; then
  log "AUTO対象の未生成トピックなし。skip（バックログにmethod系を追加すると再開）。"
  log "KOKUGO_BLOG_META status=skipped_backlog remaining=0"
  banner "ブログ自動生成" "本日は生成なし（AUTOバックログ枯渇）" "Pop"
  exit 0
fi

# 独自の切り口（ANGLE）をバックログから取得
ANGLE=$(awk -F'|' -v sl="$SLUG" '$0 ~ sl {a=$9; gsub(/^[[:space:]]+|[[:space:]]+$/,"",a); print a; exit}' CONTENT-BACKLOG.md)

# pubDate = 本日（JST）。実カレンダーに追随させ、未来日付へのドリフトを防ぐ。
# 一覧は pubDate 降順ソートなので、当日発行分は自動的に先頭に来る（1日1本運用前提）。
PUBDATE="$TODAY"

log "選定: slug=$SLUG cluster=$CLUSTER pubDate=$PUBDATE"

# ---- プロンプト組み立て（テンプレを置換） ----
PROMPT=$(sed \
  -e "s|__SLUG__|$SLUG|g" \
  -e "s|__TITLE__|$TITLE|g" \
  -e "s|__KW__|$KW|g" \
  -e "s|__CLUSTER__|$CLUSTER|g" \
  -e "s|__ANGLE__|$ANGLE|g" \
  -e "s|__PUBDATE__|$PUBDATE|g" \
  "$TMPL")
PROMPT="${PROMPT}

（本日の実日付: ${TODAY} JST。frontmatter の pubDate は本日 ${PUBDATE} を使う。）"

# ---- Claude生成（Bash/Web/MCPなし・sandbox fail-closed・bypass禁止） ----
FILE="src/content/blog/$SLUG.md"
check_sandbox_dependency bwrap "$EXPECTED_BWRAP_SHA256" || exit 0
check_sandbox_dependency socat "$EXPECTED_SOCAT_SHA256" || exit 0
CLAUDE_OUT=$(run_claude "$PROMPT" 2>>"$ERR_LOG")
CLAUDE_RC=$?
printf '%s\n' "$CLAUDE_OUT" | grep '^KOKUGO_BLOG_META' >> "$LOG_FILE" || true
if [ "$CLAUDE_RC" -ne 0 ]; then
  log "WARN: claude exited $CLAUDE_RC"
  "$NOTIFY_FAIL" "$JOB" "$CLAUDE_RC" "$ERR_LOG" "claude exited"
fi

if [ ! -f "$FILE" ]; then
  log "生成ファイルなし: $FILE（生成失敗）"
  "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "no output file"
  exit 0
fi

# 指定記事以外に変更があれば公開しない。sandbox内でもwrite-setを機械的に限定する。
UNEXPECTED=$(git status --porcelain --untracked-files=all | grep -vFx "?? $FILE" || true)
if [ -n "$UNEXPECTED" ]; then
  log "Claudeが指定記事以外を変更したため中断。"
  printf '%s\n' "$UNEXPECTED" >> "$ERR_LOG"
  "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "unexpected write-set"
  exit 0
fi

# ---- 安全ガード（1つでも×なら公開せず _drafts/ へ隔離） ----
FAILS=""
addfail() { FAILS="$FAILS; $1"; }
grep -q '水上翔平' "$FILE" && addfail "本名"
# 合格実績「系」だけを狙い撃つ（「合格ライン」「合格点」等の正当表現は弾かない）
grep -Eq '合格実績|進学実績|合格者|合格率|[0-9０-９]+[人名][^。]{0,4}合格|合格[^。]{0,4}[0-9０-９]+[人名]' "$FILE" && addfail "合格実績系"
grep -q '水上先生' "$FILE" && addfail "自称水上先生"
grep -q '，\|．' "$FILE" && addfail "，．混入"
grep -q '\*\*' "$FILE" && addfail "太字**"
grep -Eq 'この記事では|本記事では' "$FILE" && addfail "AI定型導入"
grep -Eq '0[0-9]{1,3}-?[0-9]{2,4}-?[0-9]{3,4}' "$FILE" && addfail "電話番号らしき数字"
grep -q 'lin.ee/6IRtEXI' "$FILE" || addfail "LINE導線なし"
grep -q '個別指導のご相談' "$FILE" || addfail "CTA見出しなし"
# frontmatter に許可キー以外がないか
BADKEY=$(awk 'BEGIN{c=0} /^---$/{c++; next} c==1{ if($0 ~ /^[A-Za-z_]+:/){k=$0; sub(/:.*/,"",k); if(k!="title"&&k!="description"&&k!="pubDate"&&k!="updatedDate"&&k!="heroImage") print k} }' "$FILE")
[ -n "$BADKEY" ] && addfail "frontmatter余分キー($BADKEY)"
# 本文字数（2番目の --- 以降）
BODYCHARS=$(awk 'c>=2{print} /^---$/{c++}' "$FILE" | wc -m | tr -d ' ')
if [ "$BODYCHARS" -lt 2200 ] || [ "$BODYCHARS" -gt 3800 ]; then addfail "本文字数=$BODYCHARS(範囲外)"; fi
# 内部リンク先の実在
for l in $(grep -oE '/blog/[a-z0-9-]+/' "$FILE" | sed 's#/blog/##;s#/##' | sort -u); do
  [ -f "src/content/blog/$l.md" ] || addfail "リンク切れ($l)"
done
# 外部リンクの許可ホスト以外の混入を検知（プロンプト注入による誘導リンク差し込み対策）
for h in $(grep -oE 'https?://[A-Za-z0-9.-]+' "$FILE" | sed -E 's#^https?://##' | sort -u); do
  case "$h" in
    kokugosensei.com|*.kokugosensei.com|lin.ee|*.lin.ee|amazon.co.jp|*.amazon.co.jp) ;;
    *) addfail "外部リンク疑い($h)" ;;
  esac
done
# ビルド確認
if ! npm run build >/dev/null 2>>"$ERR_LOG"; then addfail "ビルド失敗"; fi

if [ -n "$FAILS" ]; then
  mkdir -p "_drafts/needs-fix"
  mv "$FILE" "_drafts/needs-fix/$SLUG.md"
  echo "$SLUG" >> "$DONE"   # 再生成ループ防止（人間が直す）
  printf -- "- %s  %s  (要修正:%s)\n" "$TODAY" "$SLUG" "$FAILS" >> "$REPO/_drafts/REVIEW-QUEUE.md"
  log "ガード不通過 → _drafts/needs-fix へ隔離: $SLUG【$FAILS】"
  "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "guard fail: $SLUG$FAILS"
  banner "ブログ自動生成: 要確認" "$SLUG がガード不通過。_drafts/needs-fix を確認" "Basso"
  exit 0
fi

# ---- DRY_RUN: 公開せず退避して終了 ----
if [ -n "$DRY_RUN" ]; then
  mkdir -p "_drafts/dryrun"
  mv "$FILE" "_drafts/dryrun/$SLUG.md"
  log "DRY_RUN: ガード全通過。公開せず _drafts/dryrun/$SLUG.md へ退避（本文${BODYCHARS}字）。"
  echo "DRY_RUN OK: $SLUG (${BODYCHARS}字) → _drafts/dryrun/"
  exit 0
fi

# ---- 公開（commit → push）。git操作はこのシェルのみ ----
git add "$FILE"
if git commit -q -m "自動記事: $TITLE

CONTENT-BACKLOG よりVPS Claudeで自動生成（$CLUSTER）。合格実績・生徒情報・本名は不使用。" 2>>"$ERR_LOG"; then
  if git push -q origin main 2>>"$ERR_LOG"; then
    echo "$SLUG" >> "$DONE"
    printf -- "- %s  %s  https://blog.kokugosensei.com/blog/%s/  (%s字)\n" "$TODAY" "$TITLE" "$SLUG" "$BODYCHARS" >> "$PUB_LOG"
    log "公開成功: $SLUG（${BODYCHARS}字）"
    banner "ブログ自動公開" "$TITLE を公開しました" "Glass"
  else
    log "push失敗（ローカルcommit済・手動pushが必要）: $SLUG"
    "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "push failed (committed locally)"
    banner "ブログ自動公開: push失敗" "$SLUG はcommit済。手動pushが必要" "Basso"
  fi
else
  log "commit失敗（pre-commitフックでブロックの可能性）: $SLUG"
  "$NOTIFY_FAIL" "$JOB" 1 "$ERR_LOG" "commit failed"
  banner "ブログ自動公開: commit失敗" "$SLUG のcommitに失敗" "Basso"
fi

log "done ($TODAY)"
