#!/bin/bash
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
RUNNER="$REPO_DIR/_tools/auto/run.sh"
PROMPT="$REPO_DIR/_tools/auto/prompt.tmpl.md"
BACKLOG="$REPO_DIR/CONTENT-BACKLOG.md"

bash -n "$RUNNER"
grep -q -- '--sandbox workspace-write' "$RUNNER"
grep -q -- '--ephemeral' "$RUNNER"
grep -q -- '--ignore-user-config' "$RUNNER"
if grep -Eq 'bypassPermissions|dangerously-bypass-approvals-and-sandbox' "$RUNNER"; then
  echo "SELFTEST_FAIL unsafe bypass flag found" >&2
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

echo "SELFTEST_OK auto_candidates=$AUTO_CANDIDATES"
