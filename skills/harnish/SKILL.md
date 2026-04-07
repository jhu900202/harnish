---
name: harnish
version: 0.0.1
description: >
  Autonomous implementation engine. PRD to task decomposition, RALP loop autonomous execution, cross-session context preservation, experience accumulation.
  triggers: "구현 시작", "start implementation", "태스크 분해", "decompose tasks", "루프 돌려", "run loop", "이어서 진행", "continue",
  "다음 태스크", "next task", "진행 상태", "progress status", "자산 현황", "asset status", "자산 압축", "compress assets",
  "이 패턴 기억해", "remember this pattern", "스킬로 만들어", "make it a skill",
  Request to resume work when harnish-current-work.json exists.
---

# harnish — Autonomous Implementation Engine

> Do not judge. Follow the rules. When lost, return to harnish-current-work.json. When stuck, escalate. No invention.

## Skill Chain

```
drafti-architect (or drafti-feature) → harnish → ralphi
```

| Skill | Standalone Call | Prerequisites |
|-------|----------------|---------------|
| drafti-architect | Yes | None (only needs a technical problem) |
| drafti-feature | Yes | Requires a planning document |
| harnish | Yes | docs/prd-*.md or existing harnish-current-work.json |
| ralphi | Yes | Specify target files/directories to verify |

When harnish starts without a PRD: "No PRD found. Please create one first with /drafti-architect or /drafti-feature."

## Bash Convention

> bash 3.2+, python3, jq. macOS/Linux.

Each Bash tool invocation is a fresh subshell — variables do **not** survive across calls. Every bash block in this skill must re-declare `HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"` inline before using any script path. There are no persistent script-name aliases; full paths (`$HARNISH_ROOT/scripts/{name}.sh`) are used directly.

State counters (`TASK_COMPLETE_COUNT`, etc.) are tracked by the LLM in conversation memory, not in shell variables. `COMPRESS_EVERY_N = 5`.

## Step 1: Mode Detection

| Condition | Mode | Next | References to Load |
|-----------|------|------|--------------------|
| PRD provided, no harnish-current-work.json | Seeding | Step 2 | `task-schema.md` + `progress-template.md` |
| harnish-current-work.json exists | Implementation Loop | Step 3 | `escalation-protocol.md` + `guardrail-levels.md` |
| "자산 현황/압축/기억해/스킬로" | Experience | Step 5 | `thresholds.md` |
| harnish-current-work.json exists + session start | Restore | Step 4 | — |

Load **at most 2 references** at a time. (See Context Budget below.)

## Step 2: Seeding (PRD → harnish-current-work.json)

1. Verify PRD file: `docs/prd-{name}.md`. Confirm existence of §4 (Implementation Spec), §6 (Tests), §7 (Guardrails)
2. Query existing assets:
   ```bash
   HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
   bash "$HARNISH_ROOT/scripts/query-assets.sh" \
     --tags "{key}" --types guardrail --format text \
     --base-dir "$(pwd)/.harnish"
   ```
3. Phase splitting: Data → Business Logic → UI → Integration Tests
4. Task decomposition: **1 task = 1 file | 1 function | 1 test | 1 config**
5. Read `references/progress-template.md` and generate harnish-current-work.json → validate:
   ```bash
   HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
   bash "$HARNISH_ROOT/scripts/validate-progress.sh" .harnish/harnish-current-work.json
   ```
6. Report to user: "Seeding complete — {N} Phases, {M} Tasks — review and say 'run loop'"
7. → Proceed to Step 3

## Step 3: Implementation Loop (RALP)

### Entry

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/validate-progress.sh" .harnish/harnish-current-work.json
bash "$HARNISH_ROOT/scripts/loop-step.sh" .harnish/harnish-current-work.json
```
- `STATUS=ALL_DONE` → report completion → STOP
- `STATUS=NO_DOING` → move first Todo to Doing (see "Todo→Doing" below)
- `STATUS=ACTIVE` → check next action of current task → start loop

### One Loop Cycle = READ → ACT → LOG → PROGRESS

**[READ]**
- Read the doing task's objective, strategy, files, and prohibitions from harnish-current-work.json
- Query assets:
  ```bash
  HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
  bash "$HARNISH_ROOT/scripts/query-assets.sh" --tags "{task-id},{phase}" --format inject --base-dir "$(pwd)/.harnish"
  ```

**[ACT]**
- Create/modify files according to the guide
- Hard guardrail violation → immediately STOP + escalation
- Soft guardrail violation → warning + auto-correction

**[LOG]** (every 3 actions)
- Update harnish-current-work.json doing: current / last action / next action
- ```bash
  HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
  bash "$HARNISH_ROOT/scripts/validate-progress.sh" .harnish/harnish-current-work.json
  ```

**[PROGRESS]** Run acceptance_criteria:
- **Pass** → move Doing→Done → record asset (if applicable) → TASK_COMPLETE_COUNT += 1 → move next Todo→Doing → repeat loop
- **1-2 failures** → analyze cause → fix → go to [ACT]
- **3 failures** → record failure asset → **escalation. Do not attempt to resolve alone.**

### How to Run acceptance_criteria

| Form | Execution | Pass Criteria |
|------|-----------|---------------|
| bash command | Execute as-is | exit 0 |
| Condition list | Verify each condition in code | All ✓ |
| Mixed | bash first, then conditions | Both pass |
| None | **Escalation** (cannot mark Done without criteria) | — |

#### Behavior When acceptance_criteria Is Empty

The empty-criteria check is an **entry gate at every transition into Doing**, not a post-execution check:

1. **Seeding (Step 2)**: Extract criteria from PRD §6. If mapping is not possible → immediately ask the user: "Please specify acceptance_criteria for Task {id}." Do not seed the task without criteria.
2. **Todo→Doing transition**: If `acceptance_criteria` is empty or missing → escalate **before** transitioning to Doing. The task does not enter Doing.
3. **Mid-session edits**: If a task already in Doing has its criteria emptied (rare; usually a user manual edit) → escalate immediately on next loop entry, before [ACT]. This is separate from the 3-failure rule.

### Todo→Doing Transition

1. Check `.todo.phases[0].tasks[0]` (first incomplete task)
2. Verify `depends_on` is satisfied (all prerequisite Tasks exist in `.done.phases`)
3. Update harnish-current-work.json: `.doing.task = {id, title, started_at, current, next_action, blocker:null, retry_count:0, context}`, remove the task from `.todo`
4. Update `.metadata.status`
5. ```bash
   HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
   bash "$HARNISH_ROOT/scripts/validate-progress.sh" .harnish/harnish-current-work.json
   ```

### Doing→Done Transition

1. Find the same phase in `.done.phases` (add a new Phase if not found)
2. Add completed task: `{id, title, result: "one-line summary", files_changed, verification, duration}`
3. `.doing.task = null`, `.stats.completed_tasks += 1`
4. ```bash
   HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
   bash "$HARNISH_ROOT/scripts/validate-progress.sh" .harnish/harnish-current-work.json
   ```

### On Phase Completion (Milestone)

```
✅ Milestone: Phase {N} — {title}
Completed: {M} tasks / Changed: {K} files
Next: Phase {N+1} — Shall we continue?
```

Run RAG compression:
```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/compress-progress.sh" .harnish/harnish-current-work.json --trigger milestone --phase {N}
```

Counter-based compression (LLM tracks `TASK_COMPLETE_COUNT` in conversation; every 5):
```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/compress-progress.sh" .harnish/harnish-current-work.json --trigger count
```
Run the above only when `TASK_COMPLETE_COUNT % 5 == 0`. The decision to run is the LLM's; the bash invocation itself does not check the counter.

Wait for user response → "continue" → next Phase → repeat loop. All Phases Done → completion report.

### Escalation Report

```
🆘 Escalation: Task {ID} — {title}
Blocked at: {file/function/command}
Attempts: 1. {attempt}: {result} / 2. ... / 3. ...
Options: A. {A} / B. {B}
```

## Step 4: Session Restore (Anchoring)

When harnish-current-work.json exists + new session starts:

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/validate-progress.sh" .harnish/harnish-current-work.json   # verify structure integrity
bash "$HARNISH_ROOT/scripts/loop-step.sh" .harnish/harnish-current-work.json            # extract coordinates
```

If Doing exists, resume from "next action" / otherwise first Todo Task. Report then → enter Step 3 loop:
   ```
   🔄 Session restored
   Current: Phase {N} / Task {ID} — {title}
   Next: {next_action}
   ```

## Step 5: Experience Accumulation

### Asset Recording Criteria

| Condition | Type | Required/Recommended |
|-----------|------|----------------------|
| Same error 2+ times AND resolved | failure | Required |
| User says "remember/record pattern" | Corresponding type | Required |
| User says "never do ~" | guardrail | Required |
| First-try success AND generalizable | pattern | Recommended |
| A vs B choice AND clear rationale | decision | Recommended |
| Same code structure 2+ times | snippet | Recommended |
| None of the above | — | Do not record |

Recording:
```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/record-asset.sh" \
  --type {type} --tags "{task-id},{phase}" \
  --title "{one line}" --content "{content}" \
  --base-dir "$(pwd)/.harnish"
```

### Manual Triggers

| Utterance | Script |
|-----------|--------|
| "자산 현황" / "asset status" | check-thresholds.sh |
| "자산 압축" / "compress assets" | compress-assets.sh |
| "이 패턴 기억해" / "remember this pattern" | record-asset.sh --type pattern |
| "스킬로 만들어" / "make it a skill" | skillify.sh |
| "자산 품질" / "asset quality" | quality-gate.sh |
| "위반 확인" / "check violations" | check-violations.sh |

## Context Budget

| When | Reads |
|---|---|
| Step 1 (Mode Detection) | Mode-specific references only (max 2): see Mode Detection table |
| Step 2 (Seeding) | PRD file (`docs/prd-*.md`), `references/progress-template.md`, query-assets output |
| Step 3 [READ] | Current task fields from `harnish-current-work.json`, query-assets output (filtered by task tags) |
| Step 3 [ACT] | Files referenced by current task only — no exploration outside scope |
| Step 3 [LOG] | None (write-only) |
| Step 3 [PROGRESS] | Test outputs only |
| Step 4 (Restore) | `harnish-current-work.json`, no source code |
| Step 5 (Experience) | `references/thresholds.md`, asset query output |

`Load at most 2 references at a time.` Other references must wait for a phase switch.

## Guardrails

**Soft** (warning + correction):
- 100+ line file change → review task splitting
- Cannot declare Done without tests
- Cannot mark Done a task without acceptance_criteria
- Warning when modifying files outside current task scope

**Hard** (immediate STOP + escalation):
- DROP TABLE / DROP DATABASE prohibited
- Installing new packages not specified in PRD prohibited
- Inserting hardcoded secrets prohibited
- Unrelated refactoring of files outside scope prohibited
- Deleting harnish-current-work.json or directly modifying the done object prohibited

## Termination Conditions

- Todo is empty and no Doing → completion report → STOP
- User says "stop" → record current state in harnish-current-work.json → STOP
- On session end →
  ```bash
  HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
  bash "$HARNISH_ROOT/scripts/check-violations.sh" .harnish/harnish-current-work.json
  ```
