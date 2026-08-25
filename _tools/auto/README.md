# ブログ記事 自動生成＋公開パイプライン

`CONTENT-BACKLOG.md` の未生成の最上位トピックをVPS上のCodexが毎日1本生成し、安全ガードを通ったものだけ自動で公開する仕組み。

## 何を自動化するか（と、しないか）

- 自動公開する（AUTO）: 解法・悩み・学年別など事実創作リスクの低い method 系クラスタ（設問タイプ別／記述深掘り／親向けお悩み／学年別勉強法）。
- 自動化しない（要人間レビュー）: 独自資産系（志望校別・塾別・テーマ論背景知識・語彙漢字・読書）。各校の出題やNN内部など一次情報が要るため、対話で水上先生の情報を足して公開する。

## 構成ファイル

| ファイル | 役割 |
|---|---|
| `_tools/auto/run.sh` | 本体。選定→Codex生成→安全ガード→公開(commit/push)またはレビュー隔離 |
| `_tools/auto/prompt.tmpl.md` | 生成レシピ（信頼境界・NG・文体・自己点検） |
| `_tools/auto/selftest.sh` | sandbox・bypass禁止・候補選定を確認する最小self-test |
| `_tools/auto/com.shohei.kokugo-blog-auto.plist` | 旧Mac launchd定義（現在はdisabled。VPS systemdが単独owner） |
| `~/.local/state/kokugo-blog-auto/done.txt` | 生成済みslug台帳（重複防止） |
| `~/Library/Logs/automation/kokugo-blog-auto.log` | 実行ログ |
| `~/Library/Logs/automation/kokugo-blog-auto.published.log` | 公開した記事の一覧（人間用ダイジェスト） |
| `_drafts/needs-fix/` | ガード不通過で隔離された記事（要修正） |

## 安全ガード（1つでも×なら公開せず `_drafts/needs-fix/` へ隔離）

本名「水上翔平」／合格実績語／自称「水上先生」／全角，．／太字**／電話番号／LINE導線の有無／CTA見出しの有無／frontmatter余分キー／本文字数(2200〜3800)／内部リンク切れ／`npm run build` 成功。

## 現行スケジュール

- Owner: VPS systemd `kokugo-blog-auto.timer`
- 時刻: 毎日05:30 JST
- Mac `com.shohei.kokugo-blog-auto`: disabled / unloaded（二重起動防止）
- AI生成: `codex exec --sandbox workspace-write --ephemeral --ignore-user-config`

## 操作（VPS）

- 一時停止（キルスイッチ）: `touch ~/.local/state/kokugo-blog-auto/disabled`（再開は削除）
- 状態確認: `systemctl status kokugo-blog-auto.timer kokugo-blog-auto.service`
- 手動で1本テスト（公開せず）: `DRY_RUN=1 bash _tools/auto/run.sh`
- 手動で1本すぐ公開: `bash _tools/auto/run.sh`
- self-test: `bash _tools/auto/selftest.sh`

## ペースを変える

systemd timer の `OnCalendar` で時刻を変える（現状は1回1本）。変更時はMac側がdisabledのままかも確認する。

## 注意

- git pull/commit/push はrun.shが直接行い、AIにはGit操作をさせない。Codexのwrite-setは指定記事1ファイルだけか機械検査する。
- push失敗時はVPSローカルcommit済のまま通知する。その場合は状態を確認してから必要なcommitだけをpushする。
- 独自資産系を書きたいときは対話で「〇〇（志望校/塾）の記事を書いて」と言う。骨子を作って一次情報を足す運用。
