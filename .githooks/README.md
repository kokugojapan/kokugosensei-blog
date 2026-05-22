# Git Hooks for kokugosensei-blog

This directory contains shared git hooks. Enable them once after cloning:

```bash
git config core.hooksPath .githooks
```

## pre-commit

Blocks commits that contain:
- API keys / tokens (OpenAI, Anthropic, GitHub, Google, Slack, AWS, PEM keys)
- Phone numbers (Japan format)
- Unknown email addresses (only `contact@kokugosensei.com` and Anthropic noreply are allowed)
- Names listed in `blocked_names.local.txt` (gitignored — see below)
- Warns about caregiver-tone language (お子さん / 保護者 / ご家庭 / ご両親) — not blocked, just flagged

### Local blocklist for student names

Create `.githooks/blocked_names.local.txt` (gitignored) with one name per line. Lines starting with `#` are comments.

Example:
```
# Current students - block from public blog
山田太郎
鈴木花子
```

The file is git-ignored via `*.local.*` pattern in `.gitignore`, so it stays on your machine only.

### Bypass (use sparingly)

If you've reviewed a false positive and need to commit anyway:
```bash
git commit --no-verify
```
