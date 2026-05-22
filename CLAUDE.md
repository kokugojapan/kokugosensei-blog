# CLAUDE.md — kokugosensei-blog

中学受験国語ブログ（blog.kokugosensei.com）。Astro + GitHub Pages。
このリポジトリは Public。コミット内容はすべて全世界に公開されます。

## 絶対にコミットしてはいけないもの

| カテゴリ | 例 | 理由 |
|---|---|---|
| 生徒の個人情報 | 本名・通学塾・住所・電話・成績 | 個人情報保護 |
| 指導記録・議事録の引用 | AI議事録・Notion指導報告書の本文 | クライアント機密 |
| メール本文 | 保護者からのメール・Gmail本文 | 通信の秘密 |
| 内部運営情報 | bridgeStar/ThreeStars 報酬体系・先生名簿 | 取引先機密 |
| API キー・トークン | sk-... / ghp_... / AIza... | セキュリティ |
| 個人用の連絡先 | contact@kokugosensei.com 以外のメール、電話番号 | 個人情報 |

pre-commit フックが上記の多くを自動検知してブロックします。`--no-verify` でのバイパスは内容を確認してから。

## オーナー名

- 本名「水上翔平」と本名のフルネームは記事に出さない
- 公開ペンネームは「じぇい先生」のみ
- これ以外の名前を絶対に創作しない（memory: feedback_owner-name-strict 準拠）

## 書いてよいこと

- 中学受験国語の解法・教材レビュー・入試傾向
- じぇい先生メソッド（即答法／増し法／マクロ→ミクロ／ゴール設定→肉付け）の解説
- アフィリエイトリンク（A8/もしも/Amazon等、自社サービス bridgeStar/ThreeStars 含む）
- 一般的な保護者向け情報（ただし特定の生徒・家庭が想起される書き方はNG）

## 文体

- 公開ブログなので保護者向け敬体（です・ます）でOK
- 「お子さん」「保護者」「ご家庭」は記事内では使ってよい（memory の feedback_no-parent-customer-tone は指導報告書向けルールであり、公開ブログはむしろ自然）
- 国語の解法系記事は本人の語彙（即答法／増し法／マクロ→ミクロ等）で書く（memory: feedback_kokugo-output-style）

## 下書きワークフロー

- 下書きは `_drafts/` ディレクトリ（gitignore 対象）に置く
- 公開準備が整ったら `src/content/blog/` に移動 → コミット → push → GitHub Actions が自動デプロイ

## デプロイ

- main ブランチへの push で `.github/workflows/deploy.yml` が起動
- ビルド → GitHub Pages へ自動公開
- 反映は通常 1〜2 分

## カラースキーム

memory: feedback_subject-color-scheme 準拠
- 国語：赤
- 算数：青
- 理科：オレンジ
- 社会：緑

## 関連メモリ

- [[reference_kokugo-method-notion]] — じぇい先生メソッドの正典
- [[reference_kokugo-kaiho-framework]] — 解法フレーム
- [[reference_kansai-chugaku-japanese]] — 関西中学受験国語の傾向
- [[reference_kokugosensei-domain-dns]] — DNS 管理（Xserver）
- [[feedback_owner-name-strict]] — オーナー名のルール
- [[feedback_no-icons]] — 絵文字使わない
