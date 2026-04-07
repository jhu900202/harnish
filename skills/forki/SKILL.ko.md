---
name: forki
version: 0.0.1
description: >
  의사결정 강제 스킬. 문제를 역할 분해(Decision/Execution/Validation/Recovery)로
  2지선택으로 환원, trade-off를 드러내고 단일 선택을 강제.
  트리거: "결정", "선택", "어느 쪽", "두 길", "갈피", "trade-off", "둘 중 뭐",
  "이전에 결정한", "다시 결정", "결정 기록",
  "decide", "decision", "choose between", "fork", "torn between",
  "past decision", "decided before", "record decision".
  스코프: 모든 도메인. PRD 이전, 구현 이전.
---

# forki — 의사결정 강제

패턴: **2지선택 → 역할 분해 → trade-off → 강제 선택**.
설명 스킬이 아니라 **결정 스킬**.

## 모드 — HITL 전용

| 분류 | Steps | LLM 권한 |
|---|---|---|
| Auto query | 0 (조회) | 전권 |
| Flow gate | 0 (분기) | 없음 — `trust` / `reopen` |
| Verdict gate | 1, 3, 6 | 없음 — 사용자가 진술 |
| Confirmation gate | 2, 5 | 제안만 |
| Scaffold (생략 가능) | 4, 7 | 제안, 사용자 `skip` |
| Side effect (opt-out) | 8 | `y` / `n` |

LLM은 제안, 사용자가 다음 단계 전 확인. 자율 모드 없음.

> **Bash 컨벤션**: 각 Bash 호출은 새 subshell. 이 스킬의 모든 bash 블록 (`SKILL.md`와 `references/` 양쪽)이 자기 안에서 `HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"`를 인라인 선언.

## References (한 번 로드, 재사용)

| 파일 | 첫 로드 시점 | 용도 |
|---|---|---|
| `references/protocol.md` | Step 1 (첫 HITL) | 모든 HITL 프롬프트, 응답 규칙 파싱, 보고 템플릿 |
| `references/asset.md` | Step 0 진입, 또는 Step 0 생략 시 Step 8 진입 | `.harnish/` query/record bash 블록 |

각 reference는 **forki 호출당 최대 1회** 로드되며 이후 모든 step에서 재사용. 전체 read/write 목록은 아래 **Context Budget** 참조.

## Step 0: 과거 결정 조회 (선택)

→ `references/asset.md`를 로드하고 거기 문서화된 Step 0 query 블록을 **실행**한다. 전체 분기 로직 (`trust` / `reopen` / `.harnish/` 부재 시 생략 / 매칭 없을 시 생략)은 `asset.md`에 산다.

## Step 1: 2지선택

정확히 **2개**. 3개 이상 → "A 한다 vs 그 외 전부"로 압축. "상황에 따라" → 사용자에게 제약을 묻는다.

→ `references/protocol.md`의 **Step 1 prompt**로 HITL. 명시적 확인 대기. 출력: `A vs B`, 한 줄.

## Step 2: 한 줄 환원

한 문장으로 압축: *"누가 X를 실행하는가?"* / *"누가 X를 책임지는가?"* / *"X가 일어나면 무엇이 변하는가?"*

→ `references/protocol.md`의 **Step 2 prompt**로 HITL. 거부 → 대안 제안. 또 거부 → Step 1로 (2지선택 자체가 잘못됨).

## Step 3: 역할 분해 (D/E/V/R)

**진입 시** 첫 줄에 출력: `Step 3 attempt {n}/3`.
`{n}`은 1부터, Step 5/6/7에서 back-jump마다 +1. `attempt 4/3`이면 종료: *"forki could not converge after 3 back-jumps. forki 밖의 추가 컨텍스트가 필요합니다."*

각 옵션에 대해 4가지 역할 모두 채움:

| 역할 | 질문 |
|---|---|
| Decision | 누가 판단? |
| Execution | 누가 실행? |
| Validation | 누가 검증? |
| Recovery | 누가 복구? |

→ `references/protocol.md`의 **Step 3 prompt**로 HITL. LLM 초안 제안 가능, 사용자가 모든 칸 확인/덮어쓰기. 빈 `?` → 빈 칸만 다시 묻기.

## Step 4: 3가지 예시 (scaffold)

→ `references/protocol.md`의 **Step 4 prompt**로 HITL. 너무 구체적이거나 사용자가 `skip`이면 생략. 보고에 생략 사실 기록.

## Step 5: Trade-off

```
A: gains {X}, loses {Y}
B: gains {Y}, loses {X}
```

축: 유연성↔안정성, 속도↔안전, 자율↔통제.

→ `references/protocol.md`의 **Step 5 prompt**로 HITL.
- "X는 신경 안 써" → 그 축 지우고 새로 제안 (Step 5 내).
- 두 옵션이 같은 걸 얻거나 잃으면 → 진짜 trade-off 아님 → Step 3로 back-jump.

## Step 6: 강제 선택

> **선택**: Option {A|B}. 이유: {구조적 이유 한 줄}.

→ `references/protocol.md`의 **Step 6 prompt**로 HITL. LLM은 사용자 대신 답할 수 **없고**, 선호를 시사할 수도 **없다**. *"네가 골라"* → 답: *"forki는 너 대신 결정할 수 없습니다."*

진짜 못 고르면 → Step 3로 back-jump.

## Step 7: 이해 검증 (scaffold)

→ `references/protocol.md`의 **Step 7 prompt**로 HITL. 3개 다 못 답하면 → Step 3로 back-jump. `skip`이면 생략.

## Step 8: Decision 자산 기록 (부수효과, opt-out)

**Trigger**: Step 6에서 verdict가 나온 후에만 (Step 7도 생략 안 됐으면 그 후) 실행. 더 이른 step에서 forki가 abort하면 (counter 3/3, 사용자 `Stop`, Step 0 `trust` 재사용 등) Step 8은 **실행되지 않음**.

→ `references/asset.md` 로드해서 sub-step 8.0 / 8.1 / 8.2 (pre-check, HITL, 작성+기록) 사용.

부수효과지 게이트 아님: Step 6 verdict는 Step 8 결과와 무관하게 유효.

## Context Budget

forki는 **사고** 스킬이지 읽기 스킬이 아니다.

Reference 로드: 위의 **References** 섹션 참조 (단일 출처).

파일시스템 I/O:

| 동작 | 시점 |
|---|---|
| `.harnish/assets/*.jsonl` 읽기 (태그 필터) | Step 0만. 디렉토리 없으면 생략. |
| `/tmp/forki-{ts}.md` 작성 | Step 8 sub-step 8.2만, `y` 확인 후. |
| `.harnish/assets/decision-{date}.jsonl` append (1줄) | Step 8 sub-step 8.2만. |

최대 2개 reference 동시 컨텍스트 (`protocol.md` + `asset.md`).

## 금지

- Step 1에서 2개 초과 옵션
- verdict gate (Step 1, 3, 6) 어느 것이라도 건너뛰기
- Step 4 / 7을 게이트로 취급
- Step 6에서 LLM이 최종 선택
- `응` / `ok` / `yes`를 확정으로 해석. 항상 재질문.
- 침묵 위에 진행
- `둘 다` / `상황에 따라` / `나중에` 최종 선택
- 결정 전 "정보 더" 파일 읽기 (사용자 명시 요청 없는 한)
- 두 옵션이 같은 걸 얻거나 잃는 trade-off
- forki가 `.harnish/` 초기화
- 사용자 `n`인데 자산 기록. opt-out 존중.
- HITL 프롬프트나 보고 템플릿을 이 파일에 인라인 — `references/protocol.md`에 산다
- "참고로..." 식 보충 정보
- 장황한 결정 보고
