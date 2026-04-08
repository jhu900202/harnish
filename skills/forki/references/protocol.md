# forki — Protocol (HITL Prompts + Response Rules + Report Format)

> Loaded by `forki/SKILL.md` whenever a HITL prompt is issued or a response is parsed or a report is emitted.

## HITL Prompts (per step)

### Step 0 prompt — past-decision found
> *"Decided on {date}: {title}. Re-open, or trust the past choice? (reopen / trust)"*

### Step 1 prompt — binary confirmation
> *"I'm reading the choice as: **A) {opt A}** vs **B) {opt B}**. Confirm, or correct me."*

### Step 2 prompt — reduction confirmation
> *"Reduced form: *{one sentence}*. Is this the real question?"*

### Step 3 prompt — D/E/V/R fill (8 cells)
> "Fill in this table. Use a name, system, or 'nobody'. Empty not allowed."
> ```
> | Role        | Option A | Option B |
> |-------------|----------|----------|
> | Decision    | ?        | ?        |
> | Execution   | ?        | ?        |
> | Validation  | ?        | ?        |
> | Recovery    | ?        | ?        |
> ```

### Step 4 prompt — examples (scaffold)
> *"Three example cases that share this D/E/V/R structure: 1. {case}, 2. {case}, 3. {case}. Resonate, or different? (Reply `skip` to skip.)"*

### Step 5 prompt — trade-off confirmation
> *"Trade-off draft: A gains {X} loses {Y}; B gains {Y} loses {X}. Match what matters?"*

### Step 6 prompt — forced choice (THE gate)
> *"Based on the table and trade-off, **which one?** Answer A or B. No 'both', no 'depends'."*

### Step 7 prompt — comprehension check (scaffold)
> *"Quick check (`skip` to skip): 1. What is {X}? 2. Difference between A/B? 3. Who does what under each?"*

### Step 8 prompt — asset record opt-in
> *"Default tags: `{tag1},{tag2}`. Record this decision as an asset? (y / n / edit-tags)"*

## User Response Interpretation Rules

Apply at every HITL prompt.

**Clear (proceed)**:
- `A` / `B` / `Option A` → use as choice or confirmation as appropriate
- Edited table cells / explicit overrides → use verbatim
- `Yes, but change X to Y` → apply the change, re-confirm

**Ambiguous (must re-ask)**:
- `Yeah` / `OK` / `Sure` / `ㅇㅇ` / `응` → **not a confirmation**. Re-ask the specific item.
- `Both` / `Either` / `Doesn't matter` → invalid for Step 6. Re-state: *"Pick A or B."*
- `Depends` → ask: *"Depends on what?"* — that constraint becomes a Step 1 input.
- `You choose` / `Up to you` → reply: *"forki cannot decide for you. Pick A or B."*
- `I don't know` / `몰라` (Step 3 cell) → ask: *"Is the answer 'nobody', or do you need to think more?"* — only proceed on `nobody` or a name.
- Silence / unrelated → re-ask once. After 2 ignored prompts, abort: *"forki paused. Resume when you have a position on {item}."*

**Escape (terminate)**:
- `Stop` / `Cancel` → end with `forki aborted at Step {N}`.
- `Restart` → return to Step 1.

## Report Format

### Default
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
{recorded | skipped (user opt-out) | not-persisted: no .harnish in CWD | record-failed: {brief}}
```

**Skipped scaffold**: replace the section body with `_skipped_`.

### Reused (Step 0 → trust)
```
## forki Decision (reused)
Source: .harnish/assets/decision-{date}.jsonl
Title: {title} | Date: {date}
```

### Aborted
```
## forki Decision (aborted)
At Step {N} — {reason: user stop / 2 ignored prompts / restart / could not converge after 3 back-jumps}.
Last confirmed: {brief}
```
