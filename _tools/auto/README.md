# ブログ記事 自動生成＋公開パイプライン

`CONTENT-BACKLOG.md` の未生成の最上位トピックをVPS上のClaudeが毎日1本生成し、安全ガードを通ったものだけ自動で公開する仕組み。

## 何を自動化するか（と、しないか）

- 自動公開する（AUTO）: 解法・悩み・学年別など事実創作リスクの低い method 系クラスタ（設問タイプ別／記述深掘り／親向けお悩み／学年別勉強法）。
- 自動化しない（要人間レビュー）: 独自資産系（志望校別・塾別・テーマ論背景知識・語彙漢字・読書）。各校の出題やNN内部など一次情報が要るため、対話で水上先生の情報を足して公開する。

## 構成ファイル

| ファイル | 役割 |
|---|---|
| `_tools/auto/run.sh` | 本体。選定→Claude生成→安全ガード→公開(commit/push)またはレビュー隔離 |
| `_tools/auto/prompt.tmpl.md` | 生成レシピ（信頼境界・NG・文体・自己点検） |
| `_tools/auto/selftest.sh` | sandbox・bypass禁止・候補選定を確認する最小self-test |
| `_tools/auto/selftest-backlog-guard.sh` | 残数META・残り7本以下の通知・当日公開済みガードを偽repoで実走確認（selftest.shから呼ぶ。単独実行も可） |
| `~/.local/state/kokugo-blog-auto/backlog-low-notified` | 残数通知を最後に送った時刻（epoch秒）。8本以上に戻ると消える |
| `_tools/auto/com.shohei.kokugo-blog-auto.plist` | 旧Mac launchd定義（現在はdisabled。VPS systemdが単独owner） |
| `~/.local/state/kokugo-blog-auto/done.txt` | 生成済みslug台帳（重複防止） |
| `~/Library/Logs/automation/kokugo-blog-auto.log` | 実行ログ |
| `~/Library/Logs/automation/kokugo-blog-auto.published.log` | 公開した記事の一覧（人間用ダイジェスト） |
| `_drafts/needs-fix/` | ガード不通過で隔離された記事（要修正） |

## 安全ガード（1つでも×なら公開せず `_drafts/needs-fix/` へ隔離）

本名「水上翔平」／合格実績語／自称「水上先生」／全角，．／太字**／AI定型導入（「この記事では」「本記事では」）／電話番号／LINE導線の有無／CTA見出しの有無／frontmatter余分キー／本文字数(2200〜3800)／内部リンク切れ／`npm run build` 成功。

## 現行スケジュール

- Owner: VPS systemd `kokugo-blog-auto.timer`
- 時刻: 毎日05:30 JST
- Mac `com.shohei.kokugo-blog-auto`: disabled / unloaded（二重起動防止）
- 文章生成: Claude Sonnet（`dontAsk`）。Bash／Web／MCP／サブエージェントは渡さず、Read／Write／Edit／Glob／Grepだけを許可
- Claude sandbox: `enabled=true`、`failIfUnavailable=true`、`allowUnsandboxedCommands=false`、bypass無効

## 操作（VPS）

- 一時停止（キルスイッチ）: `touch ~/.local/state/kokugo-blog-auto/disabled`（再開は削除）
- 状態確認: `systemctl status kokugo-blog-auto.timer kokugo-blog-auto.service`
- 手動で1本テスト（公開せず）: `DRY_RUN=1 bash _tools/auto/run.sh`
- 手動で1本すぐ公開: `bash _tools/auto/run.sh`（その日すでに公開済みなら何もしない。下の「1日1本の安全弁」）
- self-test: `bash _tools/auto/selftest.sh`

## ペースを変える

systemd timer の `OnCalendar` で時刻を変える（現状は1回1本）。変更時はMac側がdisabledのままかも確認する。

## 1日1本の安全弁と残数の通知

- 当日公開済みなら何もしない: lock取得の直後に `kokugo-blog-auto.published.log` を見て、`- 今日の日付` の行があれば `already published today` と `KOKUGO_BLOG_META status=skipped_published_today` をログに残して exit 0 する（同じpubDateの2本目を出さない）。`DRY_RUN=1` は公開しないので対象外。
- 残数: 選定のあと `KOKUGO_BLOG_META status=selected slug=… remaining=N exhaust=YYYY-MM-DD` をログに残す。N は今日の1本を除いた未生成のAUTO候補数、exhaust は1日1本で進んだときに初めて公開0本になる日。
- 通知: N≤7 なら「残りN本（M/D に枯渇）」をSlack（Macはバナー）へ送る。同じ状態の再送は12時間あけ（初回＋継続中12時間ごと）、05:30の定時起動では1日1通。N≥8 に戻ると印を消し、次に減ったときはすぐ送る。`DRY_RUN=1` では送らない。
- 通知が来たら `CONTENT-BACKLOG.md` へ method 系を補充する（8本以上で止まる）。

## 注意

- git pull/commit/push はrun.shが直接行い、ClaudeにはGit操作をさせない。Claudeのwrite-setは指定記事1ファイルだけか機械検査する。
- VPSのsandbox部品は `~/.local/state/kokugo-blog-auto/sandbox-bin/{bwrap,socat}`。run.shがSHA-256を照合し、欠落・改変時は生成せず通知する。
- push失敗時はVPSローカルcommit済のまま通知する。その場合は状態を確認してから必要なcommitだけをpushする。
- 独自資産系を書きたいときは対話で「〇〇（志望校/塾）の記事を書いて」と言う。骨子を作って一次情報を足す運用。
