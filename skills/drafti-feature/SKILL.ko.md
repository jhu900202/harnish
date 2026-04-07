---
name: drafti-feature
version: 0.0.1
description: >
  기획 기반 구현 명세 PRD 생성기. 기획 요구사항을 구현 가능한 명세로 변환한다.
  트리거: "이 기획서로 PRD 만들어", "피쳐 PRD", "기획서 기반 구현 명세",
  "피쳐 설계", 또는 기획 문서가 첨부/참조되었을 때.
  drafti-architect와 구분: 기획 문서 있음 → feature, 없음 → architect.
---

# drafti-feature — 기획→구현 명세 PRD

> 기획 요구사항을 받아서 "어떻게 만드는가"에 집중한 구현 명세 PRD를 만든다.

## Bash 컨벤션

각 Bash 도구 호출은 새 subshell. 모든 bash 블록은 자기 안에서 `HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"`를 다시 선언; 영구 변수 없음.

## 스킬 체인

독립 호출 가능 (기획서 필요). 후속: "검토 후 '구현 시작'" → harnish, 또는 "/ralphi로 PRD 정합성 확인" → ralphi.

## Step 1: 요구사항 파싱

기획서에서 4가지를 추출한다:

| 항목 | 내용 |
|-----|------|
| 핵심 기능 | 사용자에게 보이는 변화 (1~3줄) |
| 성공 지표 | KPI/목표 (수치 또는 조건) |
| 사용자 흐름 | Happy path + 분기 |
| 비기능 요구사항 | 성능, 보안, 접근성 |

**게이트**: 4개 모두 있어야 다음 단계로.
- 0개 빠짐 → Step 2로.
- 1개 이상 빠짐 → 사용자에게 빠진 항목을 묻는다. 기본값 가정 금지. 사용자 응답 후 재평가; 여전히 빠지면 → 재질문.

## Step 2: 기존 자산 조회

핵심 키워드 3~5개 추출 후:

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
if [[ -n "$HARNISH_ROOT" ]]; then
  bash "$HARNISH_ROOT/scripts/query-assets.sh" \
    --tags "{키워드}" --format inject \
    --base-dir "$(pwd)/.harnish"
fi
```

자산 있으면 참고, 없어도 진행.

## Step 3: 코드베이스 탐색

프로젝트 설정 파일(`package.json`, `pyproject.toml`, `go.mod` 등)로 언어를 감지한 뒤, 핵심 키워드로 영향 파일을 탐색한다.

1. **키워드 검색**: 관련 코드 파일 찾기
2. **파일명 패턴**: 관련 컴포넌트/모듈 찾기
3. **데이터 모델**: 타입 정의/인터페이스/클래스 찾기

결과: 영향 파일 목록 + 데이터 모델 변경 여부 → PRD §4에 반영.

## Step 4: 피쳐플래그 판단 (선택)

**모든 기능에 플래그가 필요하지 않다.** 아래 조건에 해당할 때만 설계한다.

| 조건 | 플래그 필요 | 불필요 |
|------|-----------|--------|
| 사용자 대면 서비스, 점진적 롤아웃 필요 | ✓ | |
| 결제/금융 등 고위험 기능 | ✓ | |
| 내부 도구, CLI, 라이브러리, 인프라 | | ✓ |
| 단순 버그 수정, 리팩토링 | | ✓ |

플래그 필요 시 → `references/feature-flag-patterns.md`를 읽고:
- 플래그 키: `{feature_name}_enabled`
- 롤아웃 전략 선택 (비율/세그먼트/수동)
- 킬스위치 조건 (에러율 > 1%, p99 > 500ms 등)
- 롤백 계획

불필요 시 → §2 (플래그 설계)는 출력 PRD에서 **생략**됨. 섹션 번호 `§1, §3, §4, ...`는 변경 없음 (재번호 금지). Step 5로 진행.

## Step 5: 구현 명세 작성

**태스크 분해의 기반. 파일 경로·함수·분기 위치를 구체적으로.**

§4.1 영향 파일:
```
| 파일 경로 | 변경 유형 | 설명 | 플래그 분기 |
```

§4.2 함수/컴포넌트: 입력 → 동작 → 출력

§4.3 플래그 분기 위치 (플래그 있을 때만): 파일 | 함수 | 위치 | 조건

§4.4 데이터 모델 (DB 변경 있을 때만): 추가 필드 + 마이그레이션 + 롤백 안전성

`references/prd-template.md`를 읽고 작성.

## Step 6: 엣지케이스 + 테스트

**플래그 있을 때**: ON/OFF/부분 롤아웃 각각 분리
**플래그 없을 때**: 정상/에러/경계값으로 분리

§6 테스트 기준 (Acceptance Criteria):
- 새 기능 동작 확인
- 기존 기능 회귀 확인
- (플래그 시) 롤백 후 기존 동작 100% 복원

## Step 7: 저장 + 자산 기록

**HITL** (어떤 파일 쓰기보다도 먼저):
> "PRD 초안 준비됨: §{포함 섹션} ({플래그 있음/없음}). `docs/prd-{slug}.md`에 저장할까요? (y / n / edit-slug)"

- `n` → 종료. PRD 저장 안 됨.
- `edit-slug` → slug 묻기, 그 후 `y`.
- `y` → 아래 저장 진행.

PRD 저장 (`y` 이후만):
```bash
mkdir -p docs/
# PRD 내용을 docs/prd-{slug}.md에 작성
```

PRD 섹션 구성:
| 섹션 | 내용 |
|------|------|
| §1 | 기획 요약 |
| §2 | 플래그 설계 ← **플래그 불필요 시 생략; §3+ 번호 변경 없음** |
| §3 | 기술 설계 (영향 파일) |
| §4 | 구현 명세 |
| §5 | 엣지케이스 |
| §6 | 테스트 기준 |
| §7 | 가드레일 |
| §8 | 자산 참조 |

자산 기록:
```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
if [[ -n "$HARNISH_ROOT" ]]; then
  bash "$HARNISH_ROOT/scripts/record-asset.sh" \
    --type pattern --tags "{키워드}" \
    --title "{피쳐명} 구현 패턴" --content "{요약}" \
    --base-dir "$(pwd)/.harnish"
fi
```

## Step 8: 완료

```
✅ PRD 생성: docs/prd-{slug}.md
포함: §4 구현 명세 / §6 테스트 기준 / §7 가드레일
다음: 검토 후 "구현 시작" 또는 /ralphi로 정합성 확인.
```

## drafti-architect와의 구분

| 사용자 요청 | 판단 | 스킬 |
|-----------|------|------|
| "이 기획서 기반으로 PRD" | 기획 문서 있음 | → drafti-feature |
| "이 문제 어떻게 설계할까" | 기획 없음 | → drafti-architect |

## Context Budget

| 시점 | 읽는 것 |
|---|---|
| Step 1 (파싱) | 기획 문서, 프로젝트 설정 파일 (`package.json`, `pyproject.toml` 등) |
| Step 2 (자산 조회) | `.harnish/assets/*.jsonl`을 태그로 필터. `.harnish/` 없으면 생략. |
| Step 3 (코드베이스) | 키워드 매칭 파일만. 전체 트리 읽기 금지. |
| Step 4 (플래그) | `references/feature-flag-patterns.md` (플래그 필요 시만) |
| Step 5 (명세) | `references/prd-template.md` |
| Step 6 (테스트) | 없음 |
| Step 7 (저장 + 기록) | 없음 (쓰기만 — `docs/prd-*.md` 와 `.harnish/assets/*.jsonl`) |

reference는 **동시에 1개**까지; 단계 전환 시 교체.

## 금지

- 기획서 없이 요구사항 추측 (없으면 drafti-architect로)
- 불필요한 피쳐플래그 강제 (Step 4 판단표 따를 것)
- Step 7에서 사용자 명시 확인 없이 PRD 저장
- Step 1에서 4개 필수 항목 중 하나라도 빠진 채로 진행
- reference 2개 동시 로드
