#!/bin/bash
# 生成中に増えたブログ配下の untracked regular file だけを、公開前に復旧用領域へ退避する。
# 呼出し元は Claude 実行前に clean な worktree を確認済みであること。
set -u

REPO=${1:?repo is required}
STATE_DIR=${2:?state dir is required}
REASON=${3:?reason is required}

cd "$REPO" || exit 1
REPO_REAL=$(pwd -P)
mkdir -p "$STATE_DIR" || exit 1
STATE_REAL=$(cd "$STATE_DIR" && pwd -P) || exit 1
case "$STATE_REAL/" in
  "$REPO_REAL/"*)
    echo "KOKUGO_BLOG_QUARANTINE status=error reason=state_dir_inside_repo" >&2
    exit 64
    ;;
esac

RECOVERY_DIR=""
COUNT=0
LIST=$(mktemp "$STATE_REAL/quarantine-list.XXXXXX") || exit 1
trap 'rm -f "$LIST"' EXIT
if ! git ls-files --others --exclude-standard -z -- src/content/blog > "$LIST"; then
  exit 1
fi
while IFS= read -r -d '' path; do
  case "$path" in src/content/blog/*) ;; *) exit 1 ;; esac
  case "/$path" in */../*|*/..) exit 1 ;; esac
  # gitのuntracked一覧でも、symlinkや特殊ファイルは動かさない。
  [ -f "$path" ] && [ ! -L "$path" ] || continue

  if [ -z "$RECOVERY_DIR" ]; then
    mkdir -p "$STATE_REAL/recovery" || exit 1
    RECOVERY_DIR=$(mktemp -d "$STATE_REAL/recovery/generation.XXXXXX") || exit 1
  fi
  destination="$RECOVERY_DIR/$path"
  mkdir -p "$(dirname "$destination")" || exit 1
  mv "$path" "$destination" || exit 1
  COUNT=$((COUNT + 1))
done < "$LIST"

if [ "$COUNT" -eq 0 ]; then
  printf 'KOKUGO_BLOG_QUARANTINE status=none reason=%s\n' "$REASON"
else
  printf 'KOKUGO_BLOG_QUARANTINE status=moved reason=%s count=%s recovery=%s\n' \
    "$REASON" "$COUNT" "$RECOVERY_DIR"
fi
