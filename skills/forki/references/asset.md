# forki — Asset Persistence (Step 0 + Step 8 details)

> Loaded by `forki/SKILL.md` when entering Step 0 (past-decision query) or Step 8 (record-as-asset).

## Step 0 — Past-Decision Query

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/query-assets.sh" --types decision --tags "{topic}" --format text --base-dir "$(pwd)/.harnish" 2>/dev/null || true
```

- Skip if `.harnish/` is absent or output is empty (no match).
- If a match exists → present it to the user via the Step 0 HITL prompt (see `references/protocol.md`).
- `trust` → end forki, emit the **Reused** report template (see `references/protocol.md`).
- `reopen` → proceed to Step 1 normally.

## Step 8 — Record as Decision Asset

### 8.0 — Pre-check

`.harnish/` absent in CWD → skip the entire step. Report `not-persisted: no .harnish in CWD`. **Never initialize** `.harnish/` from forki.

### 8.1 — HITL prompt (must come before any write)

LLM proposes default tags first (kebab-case, derived from the binary topic), then asks per the Step 8 prompt in `references/protocol.md`.

Branches:
- `n` → end Step 8, report `skipped (user opt-out)`. **No file written.**
- `edit-tags` → ask: *"What tags? (comma, kebab-case)"* → use those.
- `y` → use the proposed default tags.

In both `y` and `edit-tags`, the resulting tag string is `TAGS` (LLM holds it as a literal string, not a shell variable).

### 8.2 — Write body and record (single bash invocation)

Before substituting placeholders, LLM must:
- `TAGS` and `TITLE`: prepend `\` to each of `"`, `$`, `` ` ``, `\` (safe inside bash double quotes)
- `BODY_CONTENT`: ensure no line equals exactly `FORKI_REPORT_EOF`. If it does, regenerate that line with the string broken (e.g., split across two lines). Do **not** rename the heredoc tag.

Then run **one** bash block:

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
BODY="/tmp/forki-$(date -u +%Y%m%dT%H%M%SZ).md"
cat > "$BODY" <<'FORKI_REPORT_EOF'
{BODY_CONTENT}
FORKI_REPORT_EOF
if bash "$HARNISH_ROOT/scripts/record-asset.sh" --type decision --tags "{TAGS}" --title "{TITLE}" --body-file "$BODY" --base-dir "$(pwd)/.harnish"; then
  echo "FORKI_RESULT: recorded"
else
  echo "FORKI_RESULT: record-failed (body kept at $BODY)"
fi
```

The heredoc tag is quoted (`'FORKI_REPORT_EOF'`) so `$` and backticks inside `BODY_CONTENT` are not expanded. The timestamp is computed inside the same bash invocation (no precompute).

Read the `FORKI_RESULT:` line and report accordingly in the Asset section of the default report (see `references/protocol.md`).

**Side effect, not gate**: the Step 6 verdict stands regardless of Step 8 outcome.

## What gets written where

| File | Format | Purpose |
|---|---|---|
| `/tmp/forki-{ts}.md` | Markdown | Full report body, passed to `record-asset.sh --body-file` |
| `.harnish/assets/decision-{date}.jsonl` | JSONL (1 line per asset) | Persistent asset store, queried by Step 0 |
