---
name: forki
version: 0.0.1
description: >
  Decision-forcing skill. Reduces a problem to a binary fork via role decomposition
  (Decision / Execution / Validation / Recovery), surfaces trade-offs, forces a single choice.
  Triggers: "결정", "선택", "어느 쪽", "두 길", "갈피", "trade-off", "둘 중 뭐",
  "이전에 결정한", "다시 결정", "결정 기록",
  "decide", "decision", "choose between", "fork", "torn between",
  "past decision", "decided before", "record decision".
  Scope: any domain. Pre-PRD, pre-implementation.
---

# forki — Decision Forcing

Pattern: **binary → roles → trade-off → forced choice**.
This is a decision skill, not an explanation skill.

## Mode — HITL only

| Category | Steps | LLM authority |
|---|---|---|
| Auto query | 0 (query) | Full |
| Flow gate | 0 (decision) | None — `trust` / `reopen` |
| Verdict gate | 1, 3, 6 | None — user states it |
| Confirmation gate | 2, 5 | Propose only |
| Scaffold (skippable) | 4, 7 | Propose, user `skip` |
| Side effect (opt-out) | 8 | `y` / `n` |

LLM proposes; user confirms before next step. No autonomous mode.

> **Bash note**: each Bash invocation is a fresh subshell. Every block re-declares `HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"` itself.

## Step 0: Past-Decision Query (optional)

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/query-assets.sh" --types decision --tags "{topic}" --format text --base-dir "$(pwd)/.harnish" 2>/dev/null || true
```

If a match exists → ask: *"Decided on {date}: {title}. (reopen / trust)"*
- `trust` → end, report as `## forki Decision (reused)`.
- `reopen` → Step 1.

Skip if `.harnish/` absent or no match.

## Step 1: Binary

Exactly **2 options**. 3+ → collapse to "do A vs everything else". "It depends" → ask user to constrain.

**HITL**: *"A) {opt A} vs B) {opt B}. Confirm or correct."*

Wait for explicit confirmation. Output: `A vs B`, one line.

## Step 2: One-Line Reduction

Compress to one sentence: *"Who executes X?"* / *"Who owns X?"* / *"What changes when X?"*

**HITL**: *"Reduced: {sentence}. Real question?"*

Reject → propose alternative. Reject again → back to Step 1 (binary is wrong).

## Step 3: Role Decomposition (D/E/V/R)

**On entry**, output first line: `Step 3 attempt {n}/3`.
`{n}` starts at 1; +1 on each back-jump from Step 5/6/7. On `attempt 4/3`, abort: *"forki could not converge after 3 back-jumps. Gather more context outside this skill."*

Fill all 4 roles per option:

| Role | Question |
|---|---|
| Decision | Who judges? |
| Execution | Who acts? |
| Validation | Who verifies? |
| Recovery | Who fixes when broken? |

**HITL**: *"Fill the 8 cells. Use a name, system, or 'nobody'. Empty not allowed."*
LLM may draft; user confirms or overrides each. Empty `?` → re-ask only those cells.

## Step 4: Three Examples (scaffold)

**HITL**: *"Three cases sharing this D/E/V/R structure: 1. {case}, 2. {case}, 3. {case}. Resonate, or different? (`skip` to skip.)"*

Skip when concrete enough or user says `skip`. Record skip in report.

## Step 5: Trade-off

```
A: gains {X}, loses {Y}
B: gains {Y}, loses {X}
```

Axes: flexibility↔stability, speed↔safety, autonomy↔control.

**HITL**: *"A gains {X} loses {Y}; B gains {Y} loses {X}. Match what matters?"*

User says "don't care about X" → strike axis, propose new (stay in Step 5).
Both options gain/lose the same → not real trade-off → back-jump to Step 3.

## Step 6: Forced Choice

> **Choice**: Option {A|B}. Reason: {one structural reason}.

**HITL**: *"Which one? A or B. No 'both', no 'depends'."*

LLM **must not** answer for the user, **must not** signal a preference. *"You choose"* → reply: *"forki cannot decide for you."*

User truly cannot choose → back-jump to Step 3.

## Step 7: Comprehension Check (scaffold)

**HITL**: *"Quick check (`skip` to skip): 1. What is {X}? 2. Difference between A/B? 3. Who does what under each?"*

Cannot answer all 3 → back-jump to Step 3. Skip on `skip`.

## Step 8: Record as Decision Asset (side effect, opt-out)

**8.0 Pre-check**: `.harnish/` absent in CWD → skip step, report `not-persisted: no .harnish in CWD`. Never initialize.

**8.1 HITL** (before any write): LLM proposes default tags first.
> *"Default tags: `{tag1},{tag2}`. Record? (y / n / edit-tags)"*

- `n` → end, report `skipped (user opt-out)`. **No file written.**
- `edit-tags` → ask: *"Tags? (comma, kebab-case)"* → use those.
- `y` → use defaults.

**8.2 Write + record** (single bash). Before substituting:
- TAGS/TITLE: prepend `\` to each of `"`, `$`, `` ` ``, `\` (safe inside bash double quotes)
- BODY_CONTENT: ensure no line equals exactly `FORKI_REPORT_EOF` (split it if so)

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

Quoted heredoc tag → no `$`/backtick expansion in content. Read the `FORKI_RESULT:` line and report accordingly. Step 6 verdict stands regardless of recording outcome.

## User Response Interpretation Rules

Apply at every HITL.

**Clear**: `A`/`B`/explicit edit/`Yes but change X` → use verbatim.

**Ambiguous (re-ask)**:
- `Yeah`/`OK`/`ㅇㅇ`/`응` → not a confirmation. Re-ask the specific item.
- `Both`/`Either`/`Doesn't matter` → invalid for Step 6. Re-state: *"A or B."*
- `Depends` → ask: *"On what?"* — that becomes a Step 1 input.
- `You choose` → *"forki cannot decide for you."*
- `I don't know` (Step 3 cell) → *"Is the answer 'nobody', or do you need to think more?"*
- Silence → re-ask once. After 2 ignored, abort: *"forki paused. Resume when you have a position."*

**Escape**: `Stop`/`Cancel` → `forki aborted at Step {N}`. `Restart` → Step 1.

## Context Budget

forki is a **thinking** skill, not a reading skill.

| When | Reads |
|---|---|
| Step 0 | `.harnish/assets/*.jsonl` filtered. Skip if absent. |
| Steps 1–7 | Already-loaded context. No new file reads. |
| Step 8 | Writes 1 line to `.harnish/assets/decision-{date}.jsonl`. No reads. |

## Report Format

```
## forki Decision

### Binary
A: {one-line}
B: {one-line}

### Reduction
{one sentence}

### Roles
| Role        | A | B |
|-------------|---|---|
| Decision    | {who} | {who} |
| Execution   | {who} | {who} |
| Validation  | {who} | {who} |
| Recovery    | {who} | {who} |

### Examples (when applicable)
1. {case} — {how} | 2. {case} — {how} | 3. {case} — {how}

### Trade-off
A: gains {X}, loses {Y}
B: gains {Y}, loses {X}

### Choice
**Option {A|B}** — {reason}

### Comprehension (when applicable)
Q1: {ans} | Q2: {ans} | Q3: {ans}

### Asset
{recorded | skipped (user opt-out) | not-persisted: no .harnish in CWD | record-failed: {brief reason, body kept at /tmp/forki-*.md}}
```

**Skipped scaffold**: section body → `_skipped_`.

**Reused (Step 0 trust)**:
```
## forki Decision (reused)
Source: .harnish/assets/decision-{date}.jsonl
Title: {title} | Date: {date}
```

**Aborted**:
```
## forki Decision (aborted)
At Step {N} — {reason: user stop / 2 ignored prompts / restart / could not converge after 3 back-jumps}.
Last confirmed: {brief}
```

## Prohibited

- More than 2 options in Step 1
- Skipping any verdict gate (Steps 1, 3, 6)
- Treating Steps 4/7 as gates
- LLM picking the final choice in Step 6
- Interpreting `yes`/`ok`/`응` as confirmation. Always re-ask.
- Proceeding on silence
- `Both` / `depends` / `later` as final choice
- Reading files to "gather more info" (without explicit user request)
- Trade-offs where both options gain/lose the same thing
- Initializing `.harnish/` from forki
- Recording an asset on user `n`. Honor opt-out.
- "FYI..." style supplementary information
- Verbose decision reports
