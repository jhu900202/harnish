# harnish

> Claude Code skill-based autonomous implementation engine

**harnish** (harness + ish) = "대충 하네스 비스무리한 것"

작업할수록 똑똑해지는 구현 환경. 실패가 가드레일이 되고, 패턴이 축적되며, 세션이 바뀌어도 맥락이 유실되지 않는다.

## Skills

| Skill | Command | Role |
|-------|---------|------|
| **drafti-architect** | `/drafti-architect` | 기술 주도 설계 PRD 생성 |
| **drafti-feature** | `/drafti-feature` | 기획 기반 명세 PRD 생성 |
| **harnish** | `/harnish` | 자율 구현 엔진 (시딩 + RALP 루프 + 앵커링 + 경험축적) |
| **ralphi** | `/ralphi` | 아티팩트 정합성 검증 ("이 결과물이 올바른가?") |

각 스킬은 **독립 궤도**에서 동작하며, **공유 아티팩트(파일)**로만 연결된다.

```
drafti  ──→  docs/prd-*.md  ──→  harnish  ──→  구현 코드
                                     │
                                     ├── PROGRESS.md (세션 간 영속)
                                     └── _base/assets/ (경험 축적)

ralphi  ──→  어떤 아티팩트든 검증 (PRD, SKILL.md, 스크립트, 코드)
```

## Structure

```
harnish/
├── skills/
│   ├── drafti-architect/     # 기술 설계 PRD 생성
│   ├── drafti-feature/       # 기획 명세 PRD 생성
│   ├── harnish/              # 자율 구현 (시딩/RALP/앵커링/경험)
│   └── ralphi/               # 아티팩트 검증
├── hooks/hooks.json          # Claude Code hooks
├── scripts/                  # 공용 스크립트
└── _base/assets/             # 공유 자산 저장소
```

## Install

```bash
# sh (plugin)
claude plugin install https://github.com/plz-salad-not-here/harnish

# mcpmarket
# drafti-architect, drafti-feature, harnish, ralphi 개별 설치
```

## Development

```bash
git clone https://github.com/plz-salad-not-here/harnish.git
cd harnish
git config core.hooksPath .githooks
```

Pre-commit hook이 자동으로 검증합니다:
- `shellcheck` — shell script lint
- JSON syntax — `hooks.json` 등
- SKILL.md frontmatter — `name`, `description` 필수 필드
- Script permissions — `.sh` 파일 실행 권한

## Naming

- **harnish** = harness + ish (자율 구현 엔진)
- **ralphi** = RALP (Recursive Autonomous Loop Process) + i (아티팩트 검증)
- **drafti** = draft + i (PRD 생성 — drafti-architect + drafti-feature)

## License

MIT
