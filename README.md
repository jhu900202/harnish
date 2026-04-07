# harnish

> Claude Code plugin — autonomous implementation engine

**harnish** (harness + ish) — an implementation environment that gets smarter as you work. Failures become guardrails, patterns accumulate, and context persists across sessions.

[한국어](./README.ko.md)

## Skills

| Skill | Version | Command | Role |
|-------|---------|---------|------|
| **forki** | 0.0.1 | `/harnish:forki` | Decision forcing (binary fork + D/E/V/R + trade-off, HITL only) |
| **drafti-architect** | 0.0.1 | `/harnish:drafti-architect` | Tech-driven design PRD generation |
| **drafti-feature** | 0.0.1 | `/harnish:drafti-feature` | Planning-based implementation spec PRD |
| **harnish** | 0.0.1 | `/harnish:harnish` | Autonomous implementation engine (seeding + RALP loop + anchoring + experience) |
| **ralphi** | 0.0.1 | `/harnish:ralphi` | Inspection (HITL reporting or autonomous fix) |

Each skill operates in an **independent orbit**, connected only through **shared artifacts (files)**.

```
forki   ──→  forces a binary decision (D/E/V/R + trade-off, HITL only)
                ↓
drafti  ──→  docs/prd-*.md  ──→  harnish  ──→  implementation code
                                     │
                                     └── .harnish/ (work coordinates + experience, in user project CWD)

ralphi  ──→  inspects any artifact (PRD, SKILL.md, scripts, code)
              HITL (report → wait) or autonomous (fix immediately)
```

## Usage

### 0. Decision Forcing (forki)

```
User: "Should we use Postgres or MongoDB for this?"
→ forki frames as binary → asks user to confirm A/B
→ asks user to fill the D/E/V/R table (8 cells)
→ surfaces trade-off → asks user to commit (LLM cannot decide)
→ outputs the structural reason for the choice
```

### 1. PRD Generation (Design)

```
User: "Design a Redis cache layer"
→ drafti-architect explores 2-3 design alternatives with trade-off analysis
→ generates docs/prd-redis-cache.md

User: "Create a PRD from this planning doc" (with planning document attached)
→ drafti-feature generates implementation spec PRD (feature flags only when needed)
→ generates docs/prd-user-profile-edit.md
```

### 2. Autonomous Implementation (harnish)

```
User: "Start implementation" or "Decompose tasks"
→ Decomposes PRD into atomic tasks → generates harnish-current-work.json
→ "3 Phases, 12 Tasks seeded — review then 'run the loop'"

User: "Run the loop"
→ RALP loop auto-executes (Read → Act → Log → Progress → repeat)
→ Updates harnish-current-work.json every 3 actions, milestone report on phase completion

User: (in a new session) "Continue where I left off"
→ Restores coordinates from harnish-current-work.json, auto-resumes from break point
```

### 3. Inspection (ralphi)

```
User: "Inspect this PRD"
→ Type detection (PRD) → static analysis → issue report → waits for user judgment (HITL)

User: "Inspect and fix src/cache.py"
→ Type detection (code) → analysis → immediate fix → result report (autonomous)
→ Rolls back on test failure, classifies as unfixed when intent is unclear
```

### 4. Experience Accumulation

```
User: "Remember this pattern"
→ Records as pattern asset → auto-referenced in future work

User: "Asset status"
→ Shows accumulated failure/pattern/guardrail/snippet/decision assets

User: "Make this a skill"
→ Generates reusable SKILL.md draft from compressed assets
```

## Structure

```
harnish/
├── .claude-plugin/plugin.json  # Plugin manifest
├── skills/
│   ├── forki/                  # Decision forcing (binary fork + D/E/V/R + trade-off, HITL only)
│   ├── drafti-architect/       # Tech design PRD generation
│   ├── drafti-feature/         # Planning spec PRD generation
│   ├── harnish/                # Autonomous implementation (seeding/RALP/anchoring/experience)
│   └── ralphi/                 # Inspection (HITL/autonomous)
├── hooks/hooks.json            # Claude Code hooks
├── scripts/                    # Shared scripts (16)
├── docs/                       # PRD documents
├── VERSION                     # Repo version
├── CHANGELOG.md                # Release history
└── VERSIONING.md               # Versioning policy
```

## Install

```bash
git clone https://github.com/jazz1x/harnish.git
cd your-project
claude --plugin-dir /path/to/harnish
```

Skills register as `/harnish:forki`, `/harnish:harnish`, `/harnish:drafti-architect`, `/harnish:drafti-feature`, `/harnish:ralphi`.

## Development

```bash
git clone https://github.com/jazz1x/harnish.git
cd harnish
git config core.hooksPath .githooks
```

Pre-commit hooks automatically validate:
- `shellcheck` — shell script lint
- JSON syntax — `hooks.json`, etc.
- SKILL.md frontmatter — `name`, `description`, `version` required fields
- SKILL.md version — SemVer format (`X.Y.Z`)
- Script permissions — `.sh` file execution permissions

## Versioning

Hybrid versioning: repo-level version (`VERSION`) + per-skill independent versions (`SKILL.md` frontmatter).

- SemVer 2.0.0 compliant
- Git tag on PR merge (`v0.0.1`)
- Keep a Changelog format

Details: [VERSIONING.md](./VERSIONING.md) | History: [CHANGELOG.md](./CHANGELOG.md)

## Worktrees

Each worktree gets its own `.harnish/` directory based on CWD. Work coordinates and experience are fully isolated per worktree — no shared state, no write conflicts.

```
/project/.harnish/                  ← main tree
/project/.claude/worktrees/A/.harnish/  ← worktree A
/other/path/worktree-B/.harnish/        ← worktree B (physical separation)
```

To reference experience from another worktree:
```bash
query-assets.sh --tags "docker" --base-dir /project/.harnish
```

## Naming

- **harnish** = harness + ish (autonomous implementation engine)
- **ralphi** = RALP (Recursive Autonomous Loop Process) + i (inspection)
- **drafti** = draft + i (PRD generation — drafti-architect + drafti-feature)
- **forki** = fork + i (decision forcing — binary fork + D/E/V/R + trade-off, HITL only)

## Footnote

> *"If `ralphi` already does it, a new skill is just noise —
> and distill becomes its own first victim."*

A skill called `distill` was proposed, and erased by the very principle it stood for.
That was ralphi, working.

## License

MIT
