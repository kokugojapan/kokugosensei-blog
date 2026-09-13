#!/bin/bash
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
RUNNER="$REPO_DIR/_tools/auto/run.sh"
QUARANTINE="$REPO_DIR/_tools/auto/quarantine-generated-untracked.sh"
PROMPT="$REPO_DIR/_tools/auto/prompt.tmpl.md"
BACKLOG="$REPO_DIR/CONTENT-BACKLOG.md"

bash -n "$RUNNER"
grep -q -- '--model "$CLAUDE_MODEL"' "$RUNNER"
grep -q -- '--permission-mode dontAsk' "$RUNNER"
grep -q -- '--tools "Read,Write,Edit,Glob,Grep"' "$RUNNER"
grep -q -- '"enabled":true' "$RUNNER"
grep -q -- '"failIfUnavailable":true' "$RUNNER"
grep -q -- '"allowUnsandboxedCommands":false' "$RUNNER"
grep -q -- '--strict-mcp-config' "$RUNNER"
grep -q -- "grep -Eq 'この記事では|本記事では'" "$RUNNER"
grep -q 'stdout (last 200 lines)' "$RUNNER"
grep -q 'rm -f "$CLAUDE_ERR_TMP"' "$RUNNER"
grep -q 'quarantine_generated_untracked "claude_nonzero"' "$RUNNER"
grep -q 'quarantine_generated_untracked "missing_expected_output"' "$RUNNER"
grep -q 'quarantine_generated_untracked "unexpected_write_set"' "$RUNNER"
[ "$(grep -c 'if \[ ! -f "\$FILE" \] || \[ -L "\$FILE" \]; then' "$RUNNER")" -eq 1 ]
[ "$(grep -c 'quarantine_generated_untracked "' "$RUNNER")" -eq 3 ]
grep -q 'ロードマップ文は使わず' "$PROMPT"
if grep -Eq 'bypassPermissions|dangerously-bypass-approvals-and-sandbox' "$RUNNER"; then
  echo "SELFTEST_FAIL unsafe bypass flag found" >&2
  exit 1
fi
if grep -Eq 'codex exec|CODEX_MODEL|CODEX_BIN' "$RUNNER"; then
  echo "SELFTEST_FAIL article generation must use Claude, not Codex" >&2
  exit 1
fi
grep -q 'src/content/blog/__SLUG__.md' "$PROMPT"
if grep -q '/Users/shohei/' "$PROMPT"; then
  echo "SELFTEST_FAIL Mac-only path found in prompt" >&2
  exit 1
fi

DUPLICATE_SLUGS=$(awk -F'|' '/^\| *[0-9]+ *\|/ {s=$6; gsub(/[`[:space:]]/,"",s); if (s != "") print s}' "$BACKLOG" | sort | uniq -d)
if [ -n "$DUPLICATE_SLUGS" ]; then
  echo "SELFTEST_FAIL duplicate backlog slugs: $DUPLICATE_SLUGS" >&2
  exit 1
fi

AUTO_CANDIDATES=$(awk -F'|' '
  /^\| *[0-9]+ *\|/ {
    slug=$6; gsub(/[`[:space:]]/,"",slug);
    cluster=$8; gsub(/^[[:space:]]+|[[:space:]]+$/,"",cluster);
    if (cluster ~ /設問タイプ別|記述深掘り|親向け|学年別/ && cluster !~ /志望校|塾別|テーマ論|語彙漢字|読書/ && slug != "") print slug;
  }
' "$BACKLOG" | while IFS= read -r slug; do
  if [ ! -f "$REPO_DIR/src/content/blog/$slug.md" ]; then
    printf '%s\n' "$slug"
  fi
done | wc -l | tr -d ' ')

if [ "$AUTO_CANDIDATES" -lt 1 ]; then
  echo "SELFTEST_FAIL no unpublished AUTO candidate" >&2
  exit 1
fi

# 生成前cleanを前提に、復旧対象をブログ配下のuntracked regular fileへ限定する。
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/kokugo-blog-auto-selftest.XXXXXX")
STATE=$(mktemp -d "${TMPDIR:-/tmp}/kokugo-blog-auto-state.XXXXXX")
trap 'rm -rf "$FIXTURE" "$STATE"' EXIT
git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email selftest@example.invalid
git -C "$FIXTURE" config user.name selftest
mkdir -p "$FIXTURE/src/content/blog"
printf 'tracked\n' > "$FIXTURE/src/content/blog/tracked.md"
git -C "$FIXTURE" add src/content/blog/tracked.md
git -C "$FIXTURE" commit -qm fixture

expected='src/content/blog/target article.md'
typo='src/content/blog/kokugo-moshi-fukushu-jun番.md'

# target と Unicode typo: typoとtargetを復旧領域へそのまま残す。
printf 'target body\n' > "$FIXTURE/$expected"
printf 'target body\n' > "$STATE/target-original"
: > "$FIXTURE/$typo"
: > "$STATE/typo-original"
result=$(bash "$QUARANTINE" "$FIXTURE" "$STATE" unexpected_write_set)
recovery=$(printf '%s\n' "$result" | sed -n 's/.* recovery=//p')
[ ! -e "$FIXTURE/$expected" ] && [ ! -e "$FIXTURE/$typo" ]
[ -f "$recovery/$expected" ] && [ -f "$recovery/$typo" ]
[ ! -s "$recovery/$typo" ]
cmp -s "$STATE/target-original" "$recovery/$expected"
cmp -s "$STATE/typo-original" "$recovery/$typo"

# targetだけの正常生成ではrunnerが退避ヘルパーを呼ばない（上の呼出し数3で検査）。
printf 'target body\n' > "$FIXTURE/$expected"
[ -f "$FIXTURE/$expected" ]
rm "$FIXTURE/$expected"

# tracked edit と範囲外untracked fileは退避せず、後続write-set guardをブロックし続ける。
printf 'edited\n' > "$FIXTURE/src/content/blog/tracked.md"
printf 'outside\n' > "$FIXTURE/outside artifact.txt"
ln -s "$FIXTURE/outside artifact.txt" "$FIXTURE/src/content/blog/generated link.md"
printf 'target body\n' > "$FIXTURE/$expected"
result=$(bash "$QUARANTINE" "$FIXTURE" "$STATE" tracked_and_outside)
[ -f "$FIXTURE/src/content/blog/tracked.md" ] && [ -f "$FIXTURE/outside artifact.txt" ]
[ -L "$FIXTURE/src/content/blog/generated link.md" ]
[ ! -e "$FIXTURE/$expected" ]
git -C "$FIXTURE" status --porcelain | grep -qx ' M src/content/blog/tracked.md'

# 想定出力がsymlinkならrunnerの出力検査で停止し、退避処理もそのlinkを動かさない。
ln -s "$FIXTURE/outside artifact.txt" "$FIXTURE/$expected"
result=$(bash "$QUARANTINE" "$FIXTURE" "$STATE" invalid_expected_symlink)
printf '%s\n' "$result" | grep -qx 'KOKUGO_BLOG_QUARANTINE status=none reason=invalid_expected_symlink'
[ -L "$FIXTURE/$expected" ]
rm "$FIXTURE/$expected"

# 想定targetがない失敗でも、誤った生成名を残さない。空白を含むパスもそのまま復元可能にする。
missing_expected='src/content/blog/missing target.md'
spaced_typo='src/content/blog/typo file.md'
printf 'typo\n' > "$FIXTURE/$spaced_typo"
printf 'typo\n' > "$STATE/spaced-original"
result=$(bash "$QUARANTINE" "$FIXTURE" "$STATE" missing_expected_output)
recovery=$(printf '%s\n' "$result" | sed -n 's/.* recovery=//p')
[ ! -e "$FIXTURE/$spaced_typo" ] && [ -f "$recovery/$spaced_typo" ]
cmp -s "$STATE/spaced-original" "$recovery/$spaced_typo"

echo "SELFTEST_OK auto_candidates=$AUTO_CANDIDATES"
