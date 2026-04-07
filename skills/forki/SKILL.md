---
name: forki
version: 0.0.1
description: >
  Decision-forcing skill. Reduces any complex problem to a binary fork
  via role decomposition (Decision / Execution / Validation / Recovery),
  surfaces trade-offs, and forces a single choice.
  Triggers: "결정", "선택", "어느 쪽", "두 길", "갈피", "어떻게 가야",
  "trade-off", "둘 중 뭐", "비교가 안 돼",
  "decide", "decision", "choose between", "fork", "which path", "torn between".
  Scope: any domain (tech, design, process, life). Pre-PRD, pre-implementation.
---

# forki — Decision Forcing

Universal pattern: **binary fork → role decomposition → trade-off → forced choice**.
This is not an explanation skill. It is a decision skill.

## Mode

**HITL only.** forki has no autonomous mode. The decider is always the user.
The skill structures, proposes, and challenges — but the final answer in every gated step belongs to the user.
LLM may propose candidates; **the user must confirm before the next step.**

## Step 1: Define the Binary

State the choice as **exactly 2 options**. Not 3, not "and also".

- 3+ options → collapse to 2 (best vs second-best, or "do A" vs "everything else")
- "It depends" → not a decision yet, **ask the user to constrain**
- Vague target → **Ask the user. No guessing.**

**HITL prompt**:
> "I'm reading the choice as: **A) {option A}** vs **B) {option B}**. Confirm, or correct me."

Wait for explicit confirmation. Do not proceed on silence or "yeah".

Output: `Option A vs Option B`. One line.

## Step 2: One-Line Reduction

Compress the problem to **one sentence** in one of these forms:

- "Who **executes** X?"
- "Who **owns** X?"
- "What **changes** when X?"

**HITL prompt**:
> "Reduced form: *{one sentence}*. Is this the real question?"

If user rejects → propose an alternative reduction. If user rejects again → return to Step 1, the binary is wrong.

If the problem cannot be reduced → the problem is mis-defined. Return to Step 1.

## Step 3: Role Decomposition (D/E/V/R)

For each option, fill **all 4 roles**:

| Role | Question |
|------|----------|
| **Decision** | Who judges? |
| **Execution** | Who acts? |
| **Validation** | Who verifies? |
| **Recovery** | Who fixes when it breaks? |

Empty cells = hidden risk. Force a name (person, system, agent, "nobody"). "Nobody" is a valid and important answer.

**HITL prompt** (8 cells = 4 roles × 2 options):
> "Fill in this table. Use a name, a role, a system, or 'nobody'. Empty is not allowed."
> ```
> | Role        | Option A | Option B |
> |-------------|----------|----------|
> | Decision    | ?        | ?        |
> | Execution   | ?        | ?        |
> | Validation  | ?        | ?        |
> | Recovery    | ?        | ?        |
> ```

LLM may **propose** a draft table, but the user must confirm or override every cell. If any cell remains `?` after user response → re-ask only the empty cells.

This is the verdict gate. Steps 4 and 7 are scaffold.

## Step 4: Three Examples (scaffold)

Apply the role decomposition to **3 concrete cases of different character but the same structure**.

Purpose: prove the structure is real, not a coincidence. Without 3 examples, you might be pattern-matching on 1.

**HITL prompt**:
> "Three example cases that share this D/E/V/R structure:
> 1. {case 1} — {how it plays out}
> 2. {case 2} — {how it plays out}
> 3. {case 3} — {how it plays out}
>
> Do these resonate, or should I find different ones? (Reply 'skip' to skip this step.)"

Skip allowed when: the problem is so concrete that examples add no information, OR the user replies `skip`. Record the skip in the report.

## Step 5: Trade-off Generation

State what each option **gains** and **loses** in the form:

```
Option A: gains {X}, loses {Y}
Option B: gains {Y}, loses {X}
```

Common axes: flexibility ↔ stability, exploration ↔ verification, speed ↔ safety, autonomy ↔ control.

**HITL prompt**:
> "Trade-off draft:
> - A gains *{X}*, loses *{Y}*
> - B gains *{Y}*, loses *{X}*
>
> Does this match the cost that actually matters to you?"

The trade-off must be **the user's**, not the LLM's. If user says "I don't actually care about X" → strike that axis and propose a new trade-off (stay in Step 5; do not return to Step 3).

If both options gain the same thing or lose the same thing → not a real trade-off, **return to Step 3** (role decomposition was incomplete).

## Step 6: Forced Choice

Pick **one**. State it in one line:

> **Choice**: Option {A | B}. Reason: {one structural reason from Step 3 or 5}.

**HITL prompt** (this is THE gate):
> "Based on the table and trade-off, **which one?** Answer A or B. No 'both', no 'depends'."

LLM **must not** answer this for the user. LLM may state a structural lean ("the table suggests A because..."), but the verdict is the user's. If user says "you choose" → reply: *"forki cannot decide for you. Pick A or B."*

No "both", no "depends", no "later". If user truly cannot choose, the structure is incomplete — return to Step 3.

## Step 7: Comprehension Check (scaffold)

Ask the decider 3 Socratic questions.

**HITL prompt**:
> "Quick check (skip with `skip`):
> 1. What is *{X}*? (definition)
> 2. What's the actual difference between A and B? (contrast)
> 3. Under each option, who does what? (role recall)"

If the decider cannot answer all 3 → the decision is **not internalized**. Re-walk Step 3.

Skip allowed when: the user replies `skip`.

## User Response Interpretation Rules

Apply at every HITL prompt.

**Clear responses (proceed)**:
- "A" / "B" / "Option A" → choice or confirmation as appropriate
- Edited table cells / explicit overrides → use them verbatim
- "Yes, but change X to Y" → apply the change, re-confirm

**Ambiguous responses (must re-ask)**:
- "Yeah", "OK", "Sure", "ㅇㅇ", "응" → **Do not interpret as confirmation.** Re-ask the specific item.
- "Both", "Either", "Doesn't matter" → invalid for Step 6. Re-state: *"Pick A or B."*
- "Depends" → ask: *"Depends on what?"* — that constraint becomes a Step 1 input.
- "You choose" / "Up to you" → **Do not pick.** Reply: *"forki cannot decide for you."*
- "I don't know" / "몰라" (Step 3 cell) → ask: *"Is the answer 'nobody', or do you need to think more?"* — only proceed on `nobody` or a name.
- Silence / unrelated → re-ask the same prompt verbatim once. After 2 ignored prompts, abort with: *"forki paused. Resume when you have a position on {item}."*

**Escape responses (terminate)**:
- "Stop" / "Cancel" → end with `forki aborted at Step {N}.`
- "Restart" → return to Step 1.

## Context Budget

| When | What is read |
|------|--------------|
| Step 1 (binary) | User input only. No file reads. |
| Step 2 (reduce) | Already-loaded context. |
| Step 3 (D/E/V/R) | Already-loaded context. |
| Step 4 (examples) | Memory/known cases. No new file reads unless user requests. |
| Step 5–6 | No file reads. |
| Step 7 (check) | No file reads. |

forki is a **thinking** skill, not a reading skill. Reading more does not help decide.

## Report Format

```
## forki Decision

### Binary
Option A: {one-line}
Option B: {one-line}

### Reduction
{one sentence}

### Roles
| Role        | Option A | Option B |
|-------------|----------|----------|
| Decision    | {who}    | {who}    |
| Execution   | {who}    | {who}    |
| Validation  | {who}    | {who}    |
| Recovery    | {who}    | {who}    |

### Examples (when applicable)
1. {case 1} — {how the structure plays out}
2. {case 2} — {how the structure plays out}
3. {case 3} — {how the structure plays out}

### Trade-off
Option A: gains {X}, loses {Y}
Option B: gains {Y}, loses {X}

### Choice
**Option {A | B}** — {one structural reason}

### Comprehension (when applicable)
Q1: {answer}
Q2: {answer}
Q3: {answer}
```

**Skipped scaffold**: replace the section body with `_skipped_`.

**Aborted**:
```
## forki Decision (aborted)
Aborted at Step {N} — {reason: user stop / 2 ignored prompts / restart}.
Last confirmed state: {brief}
```

## Prohibited

- More than 2 options in Step 1
- Skipping Step 3. The D/E/V/R table is the verdict gate.
- Treating Steps 4 or 7 as gates. They are scaffold; they cannot block a decision.
- **LLM picking the final choice in Step 6.** Decision belongs to the user. Always.
- Interpreting "yes/ok/응" as cell-fill or final choice. Always re-ask the specific item.
- Proceeding to next step on silence
- "Both" / "depends" / "we'll see" as final choice
- Reading files to "gather more information" before deciding (without explicit user request)
- Trade-offs where both options gain/lose the same thing
- "FYI..." style supplementary information
- Verbose decision reports
