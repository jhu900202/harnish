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

> **Bash 주의**: 각 Bash 호출은 새 subshell. 모든 블록이 자기 안에서 `HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"` 다시 선언.

## Step 0: 과거 결정 조회 (선택)

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/query-assets.sh" --types decision --tags "{주제}" --format text --base-dir "$(pwd)/.harnish" 2>/dev/null || true
```

매칭 있으면 → 묻기: *"{날짜}에 결정함: {title}. (reopen / trust)"*
- `trust` → 종료, `## forki Decision (reused)` 보고.
- `reopen` → Step 1.

`.harnish/` 없거나 매칭 없으면 생략.

## Step 1: 2지선택

정확히 **2개**. 3개 이상 → "A 한다 vs 그 외 전부"로 압축. "상황에 따라" → 사용자에게 제약을 묻는다.

**HITL**: *"A) {옵션 A} vs B) {옵션 B}. 확인 또는 정정해주세요."*

명시적 확인 대기. 출력: `A vs B`, 한 줄.

## Step 2: 한 줄 환원

한 문장으로 압축: *"누가 X를 실행하는가?"* / *"누가 X를 책임지는가?"* / *"X가 일어나면 무엇이 변하는가?"*

**HITL**: *"환원된 형태: {문장}. 진짜 질문 맞나요?"*

거부 → 대안 제안. 또 거부 → Step 1로 (2지선택 자체가 잘못됨).

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

**HITL**: *"8칸을 채워주세요. 이름, 시스템, 또는 '아무도 없음'. 빈 칸 금지."*
LLM 초안 제안 가능, 사용자가 모든 칸 확인/덮어쓰기. 빈 `?` → 빈 칸만 다시 묻기.

## Step 4: 3가지 예시 (scaffold)

**HITL**: *"이 D/E/V/R 구조를 공유하는 3가지 사례: 1. {사례}, 2. {사례}, 3. {사례}. 와닿나요, 다른 거? (`skip`이면 건너뜀.)"*

너무 구체적이거나 사용자가 `skip`이면 생략. 보고에 생략 사실 기록.

## Step 5: Trade-off

```
A: gains {X}, loses {Y}
B: gains {Y}, loses {X}
```

축: 유연성↔안정성, 속도↔안전, 자율↔통제.

**HITL**: *"A는 {X} 얻고 {Y} 잃고; B는 {Y} 얻고 {X} 잃음. 너에게 의미 있는 비용 맞나요?"*

"X는 신경 안 써" → 그 축 지우고 새로 제안 (Step 5 내).
두 옵션이 같은 걸 얻거나 잃으면 → 진짜 trade-off 아님 → Step 3로 back-jump.

## Step 6: 강제 선택

> **선택**: Option {A|B}. 이유: {구조적 이유 한 줄}.

**HITL**: *"어느 쪽? A 또는 B. '둘 다', '상황에 따라' 안 됩니다."*

LLM은 사용자 대신 답할 수 **없고**, 선호를 시사할 수도 **없다**. *"네가 골라"* → 답: *"forki는 너 대신 결정할 수 없습니다."*

진짜 못 고르면 → Step 3로 back-jump.

## Step 7: 이해 검증 (scaffold)

**HITL**: *"빠른 확인 (`skip`): 1. {X}는 무엇? 2. A/B 차이? 3. 각 옵션에서 누가 무엇?"*

3개 다 못 답하면 → Step 3로 back-jump. `skip`이면 생략.

## Step 8: Decision 자산 기록 (부수효과, opt-out)

**8.0 Pre-check**: CWD에 `.harnish/` 없으면 → Step 8 생략, 보고 `not-persisted: no .harnish in CWD`. 초기화 금지.

**8.1 HITL** (어떤 쓰기보다도 먼저): LLM이 기본 태그 먼저 제안.
> *"기본 태그: `{tag1},{tag2}`. 기록할까요? (y / n / edit-tags)"*

- `n` → 종료, 보고 `skipped (user opt-out)`. **파일 작성 금지.**
- `edit-tags` → 묻기: *"태그? (콤마, kebab-case)"* → 그것 사용.
- `y` → 기본 태그 사용.

**8.2 작성 + 기록** (단일 bash). 치환 전:
- TAGS/TITLE: `"`, `$`, `` ` ``, `\` 각각 앞에 `\` 추가 (bash 더블쿼트 안에서 안전)
- BODY_CONTENT: 어느 줄도 정확히 `FORKI_REPORT_EOF`와 일치하지 않게 (충돌 시 그 줄 분할)

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
BODY="/tmp/forki-$(date -u +%Y%m%dT%H%M%SZ).md"
cat > "$BODY" <<'FORKI_REPORT_EOF'
{BODY_CONTENT}
FORKI_REPORT_EOF
if bash "$HARNISH_ROOT/scripts/record-asset.sh" --type decision --tags "{TAGS}" --title "{TITLE}" --body-file "$BODY" --base-dir "$(pwd)/.harnish"; then
  echo "FORKI_RESULT: recorded"
else
  echo "FORKI_RESULT: record-failed (body kept at $BODY)"
fi
```

quoted heredoc → 내용 안의 `$`/backtick 확장 안 됨. `FORKI_RESULT:` 줄을 읽고 그에 맞게 보고. Step 6 verdict는 기록 결과와 무관하게 유효.

## 사용자 응답 해석 규칙

모든 HITL에 적용.

**명확**: `A`/`B`/명시적 수정/`응 근데 X 바꿔` → 그대로 사용.

**모호 (재질문)**:
- `응`/`그래`/`ㅇㅇ`/`Yeah`/`OK` → 확정 아님. 해당 항목 다시 묻기.
- `둘 다`/`어느 쪽이든`/`상관없어` → Step 6에서 무효. 다시 진술: *"A 또는 B."*
- `상황에 따라` → 묻기: *"어떤 상황?"* — 그게 Step 1 입력.
- `네가 골라` → *"forki는 너 대신 결정할 수 없습니다."*
- `몰라` (Step 3 셀) → *"답이 '아무도 없음'인가요, 더 생각해봐야 하나요?"*
- 침묵 → 1회 재질문. 2번 무시되면 종료: *"forki 일시정지. 입장 생기면 재개하세요."*

**탈출**: `그만`/`취소` → `forki aborted at Step {N}`. `다시` → Step 1.

## Context Budget

forki는 **사고** 스킬이지 읽기 스킬이 아니다.

| 시점 | 읽는 것 |
|---|---|
| Step 0 | `.harnish/assets/*.jsonl` 필터. 없으면 생략. |
| Step 1–7 | 이미 로드된 컨텍스트. 새 파일 읽기 없음. |
| Step 8 | `.harnish/assets/decision-{date}.jsonl`에 1줄 쓰기. 읽기 없음. |

## 보고 포맷

```
## forki Decision

### Binary
A: {한 줄}
B: {한 줄}

### Reduction
{한 문장}

### Roles
| 역할        | A | B |
|-------------|---|---|
| Decision    | {누구} | {누구} |
| Execution   | {누구} | {누구} |
| Validation  | {누구} | {누구} |
| Recovery    | {누구} | {누구} |

### Examples (해당시)
1. {사례} — {적용} | 2. {사례} — {적용} | 3. {사례} — {적용}

### Trade-off
A: gains {X}, loses {Y}
B: gains {Y}, loses {X}

### Choice
**Option {A|B}** — {이유}

### Comprehension (해당시)
Q1: {답} | Q2: {답} | Q3: {답}

### Asset
{recorded | skipped (user opt-out) | not-persisted: no .harnish in CWD | record-failed: {짧은 사유, body는 /tmp/forki-*.md에 보존}}
```

**Scaffold 생략시**: 섹션 본문 → `_skipped_`.

**Reused (Step 0 trust)**:
```
## forki Decision (reused)
Source: .harnish/assets/decision-{date}.jsonl
Title: {title} | Date: {date}
```

**Aborted**:
```
## forki Decision (aborted)
At Step {N} — {사유: user stop / 2 ignored prompts / restart / could not converge after 3 back-jumps}.
마지막 확정: {요약}
```

## 금지

- Step 1에서 2개 초과 옵션
- verdict gate (Step 1, 3, 6) 어느 것이라도 건너뛰기
- Step 4/7을 게이트로 취급
- Step 6에서 LLM이 최종 선택
- `응`/`ok`/`yes`를 확정으로 해석. 항상 재질문.
- 침묵 위에 진행
- `둘 다` / `상황에 따라` / `나중에` 최종 선택
- 결정 전 "정보 더" 파일 읽기 (사용자 명시 요청 없는 한)
- 두 옵션이 같은 걸 얻거나 잃는 trade-off
- forki가 `.harnish/` 초기화
- 사용자 `n`인데 자산 기록. opt-out 존중.
- "참고로..." 식 보충 정보
- 장황한 결정 보고
