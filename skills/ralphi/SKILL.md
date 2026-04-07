---
name: ralphi
version: 0.0.1
description: >
  Inspection skill. Triggers: "점검해", "확인해", "검증해", "ralphi",
  "셀프점검", "커버리지 확인", "테스트 갭",
  "고쳐", "수정해", "점검하고 고쳐", "자동으로 처리해",
  "inspect", "check", "verify", "self-check",
  "coverage check", "test gap",
  "fix", "repair", "inspect and fix", "handle automatically"
---

# ralphi — Inspection

## Step 1: Mode Determination

Utterance contains "고쳐", "수정해", "fix", "처리해" → **Autonomous** (proceeds to fix)
Otherwise → **HITL** (report only and wait)

## Step 2: Scope Determination

- File path given → **File scope** → Step 3A
- Directory given → **Directory scope** → Step 3B
- Nothing given → **Ask the user**: *"Provide a file path or directory path. (`everything` / `all` are not valid scopes — pick a concrete target.)"* No guessing. Do not run git diff on your own.

## Step 3A: File Inspection

1. Detect type → determine criteria file:
   - `docs/prd-*.md` (check §section structure) → `criteria-prd.md`
   - `*/SKILL.md` (check frontmatter name:) → `criteria-skill.md`
   - `*.sh` (check shebang #!/) → `criteria-script.md`
   - `.py .ts .js .go` etc. source code → `criteria-code.md`
   - Unclear → **Ask the user**: *"Detected file `{path}` — what type? (prd / skill / script / code / other?)"* No guessing.
2. Load only **1** criteria from `references/`. Do not read other criteria.
3. Static analysis (structure, format, contract violations)
4. Dynamic execution (if script/code)
5. **Necessity check (Socratic)** — see method below.
6. → Proceed to Step 4

## Step 3B: Project/Directory Inspection

1. Run tests. Tests before reading code. If test runner is unknown, **ask the user**: *"What is the test command? (e.g. `pytest`, `npm test`, `go test ./...`, `cargo test`, custom?)"* No guessing. Tool not installed (command not found) → SKIP that check + warn. **Do not attempt installation.**
2. List changed files (git diff)
3. Analyze **only the diff** of each file. **Do not read entire files.**
4. Scenario walkthrough (intent vs implementation). Read only the relevant function. No call graph tracing.
5. Coverage gap exploration
6. **Necessity check (Socratic)** — see method below. Apply per diff hunk instead of per component.
7. → Proceed to Step 4

## Necessity Check (Socratic) — shared method

Used by Step 3A.5 (per component) and Step 3B.6 (per diff hunk).

Ask the four questions:

1. **Why** is this here? — *(purpose)*
2. **What** is it composed of? — *(composition, scaffold for Q1/Q4)*
3. **What is it really**, stripped of framing? — *(truth, scaffold for Q1/Q4)*
4. What happens **if it's removed**? — *(necessity)*

**Verdict**: Q1 and Q4 are the only gates. Q2 and Q3 are scaffolding to reach honest answers.
Items that fail Q1 or Q4 → `[warning] unjustified existence` (kept only by convention / inheritance / authority).

## Step 4: Mode Branch

### HITL Case

Report in Step 5 format → wait for user judgment.

#### User Response Interpretation Rules

Clear instructions (execute immediately):
- "Fix #1" → fix that issue only → test → report.
- "Fix 1, 3" → fix those issues sequentially, test after each.
- "Fix all" → fix all sequentially, test after each.
- "Ignore" / "Skip" → record the issue and end.

Ambiguous responses (must re-ask):
- "Yeah", "Got it", "Sure", "OK" → **Do not interpret as permission to fix.**
  → Re-ask: "Which issues should I fix? Specify numbers or say 'fix all'."
- Response unrelated to issues → re-ask.

### Autonomous Case

Fix immediately in critical→warning→coverage order → test after each fix → report results in Step 5 format when all done.
- Test FAIL → rollback that fix, unfixed "test failure"
- Intent unclear (code deletion, logic change) → unfixed "intent unclear"
- Structural change needed (file move, interface change) → unfixed "structural change needed"

**Fix prefers subtraction.** Default action for `[unjustified existence]` is removal. For `[critical/warning]` violations, **minimal additive patches are allowed** (null check, missing import, type fix, error guard) when needed to satisfy the criteria. Do **not** introduce new abstractions, modules, or features. If a fix would require new abstraction/module/feature, mark as `[unfixed] structural change required`.

If there are unfixed items, hand off to user judgment.

## Step 5: Report

Severity: `critical` (behavioral error) / `warning` (potential issue) / `coverage` (test gap)

HITL:
```
## ralphi Inspection Results
Target: {path | "user-specified scope"}
### Findings ({N} items)
1. [{severity}] {file:line} — {one-line cause}
Which issues should I fix first?
```

Autonomous:
```
## ralphi Inspection + Fix Results
Target: {path | "user-specified scope"}
### Fixed ({M}/{N} items)
1. [fixed] {file:line} — {one-line fix description}
### Unfixed ({K} items) ← only when present
1. [{severity}] {file:line} — {cause} → {reason unfixed}
Tests: {PASS | FAIL (details)}
```

No issues found → `ralphi inspection complete, no issues found.` Single line. No enumeration.

## Context Budget

| When | What is read |
|------|--------------|
| Step 3A (file inspection) | Exactly **1** criteria file from `references/`, matched to detected type. No others. |
| Step 3B (project inspection) | `git diff` only. **No full file reads.** Read only the function relevant to a scenario walkthrough. |
| Necessity check | Operates on already-loaded content. No new file reads. |
| Step 5 (report) | No file reads. Output only. |

## Prohibited

- Reading unchanged files
- Loading 2 or more criteria simultaneously
- Fixing without instructions in HITL mode
- Reading entire files in project scope (diff only)
- "FYI..." style supplementary information
- Verbose reports
