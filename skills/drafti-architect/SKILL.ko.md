---
name: drafti-architect
version: 0.0.1
description: >
  기술 설계 PRD 생성기. 기획 문서 없이 기술 문제 정의만으로 구현 가능한 PRD를 생성한다.
  트리거: "설계해", "아키텍처 PRD", "이 문제 어떻게 해결할지",
  "기술적으로 어떻게", "PRD 만들어" (기획서 미제공 시).
  drafti-feature와 구분: 기획 문서 없음 → architect, 있음 → feature.
---

# drafti-architect — 기술 설계 PRD

> 기획 없이 기술 문제에서 설계 판단을 내리고 구현 가능한 PRD를 만든다.

## Bash 컨벤션

각 Bash 도구 호출은 새 subshell. 모든 bash 블록은 자기 안에서 `HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"`를 다시 선언; 영구 변수 없음.

## 스킬 체인

독립 호출 가능. 후속: "검토 후 '구현 시작'" → harnish, 또는 "/ralphi로 PRD 정합성 확인" → ralphi.

## Step 1: 문제 명확화

사용자 입력에서 5개 항목을 검사한다. 이미 답이 있으면 넘어간다.

| # | 항목 | 검사 기준 |
|---|------|----------|
| 1 | 문제 정의 | "무엇이 문제인가" + 구체적 고통점이 있는가? |
| 2 | 긴급도 | "왜 지금 해결해야 하는가"가 있는가? |
| 3 | 기술 제약 | 스택/호환성 요구사항이 있는가? (없으면 "제약 없음"으로 진행) |
| 4 | 범위 | "이번에 할 것" vs "나중에 할 것" 구분이 있는가? |
| 5 | 성공 기준 | 완성 판정 방법이 있는가? |

- ❌인 항목만 질문. ✅인 항목은 건너뜀.
- **1~2개씩, 총 2회 이내로 완료.** 미응답 항목은 "[미확인]" 표기 후 진행.

## Step 2: 기존 자산 조회

문제에서 태그 3~5개 추출 (기술 스택 → 문제 도메인 → 작업 유형 순).

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
if [[ -n "$HARNISH_ROOT" ]]; then
  bash "$HARNISH_ROOT/scripts/query-assets.sh" \
    --tags "{추출 태그}" --format inject \
    --base-dir "$(pwd)/.harnish"
fi
```

- 자산 발견 → guardrail은 §7에, decision은 §2 보강, failure는 §5에 반영
- 빈 결과 → 자산 없이 진행

## Step 3: 설계 대안 탐색

**반드시 2개 이상** 대안 생성. "명백한 정답"이 있어도 대안을 만든다.

대안 발굴: 기존 도구? 직접 구현? 아키텍처 변경? 현상 유지? 단계적 접근?

각 대안마다:
```
## 대안 {A/B/C}: {이름}
| 측면 | 평가 |
|------|------|
| 장점 | (정량화 가능하면 정량화) |
| 단점 | (비용, 리스크, 한계) |
| 구현 난이도 | 낮음/중간/높음 + 이유 |
| 적합한 상황 | 언제 이것이 최선인가 |
| 기각 조건 | 언제 이것을 쓰면 안 되는가 |
```

상세: `references/design-decision.md`

## Step 4: 선택 + PRD 작성

### 선택 근거 — 반드시 조건형으로:

나쁜 예: "A가 더 낫다"
좋은 예: "팀 React 경험 2년 + 기존 코드 80% → 학습 비용 제로. Vue는 3주 학습 필요. 따라서 React."

필수: 현재 상황 명시 → 선택으로 얻는 것 → **유효 조건** ("이 조건이 변하면 재검토")

### PRD 규모 판단 → 섹션 결정

| 규모 | 기준 | 필수 섹션 | 선택 |
|------|------|----------|------|
| 소 (1~2일) | <500줄 | §1, §2, §4, §6, §7 | §3, §5 |
| 중 (1~2주) | 500~2000줄 | §1~§8 전체 | §9 |
| 대 (1개월+) | 2000줄+ | §1~§8 + 페이즈 분할 | 일정표 |

불명확하면 → **사용자에게 묻는다**: *"규모: 소(1-2일), 중(1-2주), 대(1개월+) 중 어느 것?"* 침묵 가정 금지. `references/prd-template.md`를 읽고 작성.

## Step 5: 저장 + 자산 기록

**HITL** (어떤 파일 쓰기보다도 먼저):
> "PRD 초안 준비됨: §{섹션} / {규모}. `docs/prd-{slug}.md`에 저장할까요? (y / n / edit-slug)"

- `n` → 종료. PRD 저장 안 됨.
- `edit-slug` → slug 묻기, 그 후 `y`.
- `y` → 아래 저장 진행.

PRD 저장 (`y` 이후만):
```bash
mkdir -p docs/
# PRD 내용을 docs/prd-{slug}.md에 작성
```

자산 기록 (harnish 생태계 모드):
```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
if [[ -n "$HARNISH_ROOT" ]]; then
  # Decision 기록
  bash "$HARNISH_ROOT/scripts/record-asset.sh" \
    --type decision --tags "{태그}" \
    --title "{결정 한 줄}" --content "{선택 근거}" \
    --base-dir "$(pwd)/.harnish"

  # Guardrail 기록 (도출된 제약이 있을 때)
  bash "$HARNISH_ROOT/scripts/record-asset.sh" \
    --type guardrail --tags "{태그}" \
    --title "{규칙 한 줄}" --content "{위반 시 결과}" \
    --base-dir "$(pwd)/.harnish"
fi
```

## Step 6: 완료

```
✅ PRD 완성: docs/prd-{slug}.md
포함: §4 구현 명세 / §6 테스트 기준 / §7 가드레일
다음: 검토 후 "구현 시작" 또는 /ralphi로 정합성 확인.
```

## drafti-feature와의 구분

| 사용자 요청 | 판단 | 스킬 |
|-----------|------|------|
| "이 기획서 기반으로 PRD" | 기획 문서 있음 | → drafti-feature |
| "이 문제 어떻게 설계할까" | 기획 없음, 설계 판단 필요 | → drafti-architect |

기획 문서 유/무로 판단. 의심스러우면 사용자에게 "기획 문서가 있나요?"

## Context Budget

| 시점 | 읽는 것 |
|---|---|
| Step 1 (명확화) | 사용자 입력만 |
| Step 2 (자산 조회) | `.harnish/assets/*.jsonl`을 태그로 필터. `.harnish/` 없으면 생략. |
| Step 3 (대안) | `references/design-decision.md` |
| Step 4 (선택 + PRD) | `references/prd-template.md` |
| Step 5 (저장 + 기록) | 없음 (쓰기만 — `docs/prd-*.md` 와 `.harnish/assets/*.jsonl`) |

reference는 **동시에 1개**까지; 단계 전환 시 교체.

## 금지

- 대안 1개만으로 끝내기 (최소 2개)
- "~가 더 낫다" 식 근거 없는 선택
- 유효 조건 없이 결정 확정
- Step 5에서 사용자 명시 확인 없이 PRD 저장
- 규모 불명확한데 침묵으로 가정
- reference 2개 동시 로드
