# harnish

> Claude Code plugin — autonomous implementation engine

**harnish** (harness + ish) = "대충 하네스 비스무리한 것"

작업할수록 똑똑해지는 구현 환경. 실패가 가드레일이 되고, 패턴이 축적되며, 세션이 바뀌어도 맥락이 유실되지 않는다.

## Skills

| Skill | Version | Command | Role |
|-------|---------|---------|------|
| **forki** | 0.0.1 | `/forki` | 의사결정 강제 (2지선택 + D/E/V/R + trade-off, HITL 전용) |
| **drafti-architect** | 0.0.1 | `/drafti-architect` | 기술 주도 설계 PRD 생성 |
| **drafti-feature** | 0.0.1 | `/drafti-feature` | 기획 기반 구현 명세 PRD 생성 |
| **harnish** | 0.0.1 | `/harnish` | 자율 구현 엔진 (시딩 + RALP 루프 + 앵커링 + 경험축적) |
| **ralphi** | 0.0.1 | `/ralphi` | 점검 (HITL 보고 또는 자율 수정) |

각 스킬은 **독립 궤도**에서 동작하며, **공유 아티팩트(파일)**로만 연결된다.

```
forki   ──→  2지선택 강제 (D/E/V/R + trade-off, HITL 전용)
                ↓
drafti  ──→  docs/prd-*.md  ──→  harnish  ──→  구현 코드
                                     │
                                     └── .harnish/ (작업 좌표 + 경험 축적, 사용자 프로젝트 CWD)

ralphi  ──→  어떤 아티팩트든 점검 (PRD, SKILL.md, 스크립트, 코드)
              HITL(보고→대기) 또는 자율(즉시 수정)
```

## Usage

### 0. 의사결정 강제 (forki)

```
사용자: "Postgres와 MongoDB 중 뭐 써야 하지?"
→ forki가 2지선택으로 정리 → A/B 사용자 확정
→ D/E/V/R 표 8칸 사용자에게 채우라고 요청
→ trade-off 도출 → 최종 선택은 사용자 (LLM은 결정 못 함)
→ 선택의 구조적 이유 출력
```

### 1. PRD 생성 (설계)

```
사용자: "Redis 캐시 레이어 설계해줘"
→ drafti-architect가 설계 대안 2~3개 탐색, 트레이드오프 분석
→ docs/prd-redis-cache.md 생성

사용자: "이 기획서로 PRD 만들어" (기획 문서 첨부)
→ drafti-feature가 구현 명세 PRD 생성 (피쳐플래그는 필요 시만)
→ docs/prd-user-profile-edit.md 생성
```

### 2. 자율 구현 (harnish)

```
사용자: "구현 시작" 또는 "태스크 분해"
→ PRD를 원자적 태스크로 분해 → harnish-current-work.json 생성
→ "Phase 3개, Task 12개 시딩 완료 — 확인 후 '루프 돌려'"

사용자: "루프 돌려"
→ RALP 루프 자동 실행 (Read → Act → Log → Progress → repeat)
→ 매 3액션마다 harnish-current-work.json 갱신, Phase 완료 시 마일스톤 보고

사용자: (새 세션에서) "이어서 진행"
→ harnish-current-work.json에서 좌표 복원, 중단 지점부터 자동 재개
```

### 3. 점검 (ralphi)

```
사용자: "이 PRD 점검해"
→ 타입 감지 (PRD) → 정적 분석 → 이슈 보고 → 사용자 판단 대기 (HITL)

사용자: "src/cache.py 점검하고 고쳐"
→ 타입 감지 (코드) → 분석 → 즉시 수정 → 결과 보고 (자율)
→ 테스트 FAIL 시 롤백, 의도 불명확 시 미수정 분류
```

### 4. 경험 축적

```
사용자: "이 패턴 기억해"
→ pattern 자산으로 기록 → 이후 작업에서 자동 참조

사용자: "자산 현황"
→ 축적된 failure/pattern/guardrail/snippet/decision 현황 조회

사용자: "스킬로 만들어"
→ 압축된 자산에서 재사용 가능한 SKILL.md 초안 생성
```

## Structure

```
harnish/
├── .claude-plugin/plugin.json  # 플러그인 매니페스트
├── skills/
│   ├── forki/                  # 의사결정 강제 (2지선택 + D/E/V/R + trade-off, HITL 전용)
│   ├── drafti-architect/       # 기술 설계 PRD 생성
│   ├── drafti-feature/         # 기획 명세 PRD 생성
│   ├── harnish/                # 자율 구현 (시딩/RALP/앵커링/경험)
│   └── ralphi/                 # 점검 (HITL/자율)
├── hooks/hooks.json            # Claude Code hooks
├── scripts/                    # 공용 스크립트 (16개)
├── docs/                       # PRD 문서
├── VERSION                     # 리포 버전
├── CHANGELOG.md                # 릴리스 이력
└── VERSIONING.md               # 버저닝 정책
```

## Install

```bash
git clone https://github.com/jazz1x/harnish.git
cd your-project
claude --plugin-dir /path/to/harnish
```

스킬은 `/harnish:forki`, `/harnish:harnish`, `/harnish:drafti-architect`, `/harnish:drafti-feature`, `/harnish:ralphi`로 등록됩니다.

## Development

```bash
git clone https://github.com/jazz1x/harnish.git
cd harnish
git config core.hooksPath .githooks
```

Pre-commit hook이 자동으로 검증합니다:
- `shellcheck` — shell script lint
- JSON syntax — `hooks.json` 등
- SKILL.md frontmatter — `name`, `description`, `version` 필수 필드
- SKILL.md version — SemVer 포맷 (`X.Y.Z`) 검증
- Script permissions — `.sh` 파일 실행 권한

## Versioning

혼합 버저닝: 리포 전체 버전(`VERSION`) + 스킬별 독립 버전(`SKILL.md` frontmatter).

- SemVer 2.0.0 준수
- PR 머지 시 git tag (`v0.0.1`)
- Keep a Changelog 포맷

상세: [VERSIONING.md](./VERSIONING.md) | 이력: [CHANGELOG.md](./CHANGELOG.md)

## 워크트리

워크트리마다 CWD 기준으로 독립된 `.harnish/` 디렉토리가 생성됩니다. 작업 좌표와 경험 자산 모두 워크트리별로 완전 격리되어, 공유 상태나 쓰기 충돌이 없습니다.

```
/project/.harnish/                      ← 메인 트리
/project/.claude/worktrees/A/.harnish/  ← 워크트리 A
/other/path/worktree-B/.harnish/        ← 워크트리 B (물리적 분리)
```

다른 워크트리의 경험을 참조하려면:
```bash
query-assets.sh --tags "docker" --base-dir /project/.harnish
```

## Naming

- **harnish** = harness + ish (자율 구현 엔진)
- **ralphi** = RALP (Recursive Autonomous Loop Process) + i (점검)
- **drafti** = draft + i (PRD 생성 — drafti-architect + drafti-feature)
- **forki** = fork + i (의사결정 강제 — 2지선택 + D/E/V/R + trade-off, HITL 전용)

## Footnote

> *"`ralphi`가 이미 하는 일이라면, 새 스킬은 노이즈일 뿐이다 —
> distill은 자기 자신의 첫 희생자가 된다."*

`distill`이라는 스킬이 제안됐고, 자신이 내세운 원리에 의해 지워졌다.
그게 바로 ralphi가 작동한 순간이었다.

## License

MIT
