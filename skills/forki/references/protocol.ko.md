# forki — 프로토콜 (HITL 프롬프트 + 응답 규칙 + 보고 포맷)

> `forki/SKILL.md`가 HITL 프롬프트 발행, 응답 파싱, 보고 출력 시마다 로드.

## HITL 프롬프트 (step별)

### Step 0 prompt — 과거 결정 발견 시
> *"{날짜}에 결정함: {title}. 다시 열까요, 과거 선택을 신뢰할까요? (reopen / trust)"*

### Step 1 prompt — 2지선택 확인
> *"선택을 다음과 같이 읽었습니다: **A) {옵션 A}** vs **B) {옵션 B}**. 확인 또는 정정해주세요."*

### Step 2 prompt — 환원 확인
> *"환원된 형태: *{한 문장}*. 진짜 질문 맞나요?"*

### Step 3 prompt — D/E/V/R 채우기 (8칸)
> "다음 표를 채워주세요. 이름, 시스템, 또는 '아무도 없음'. 빈 칸 금지."
> ```
> | 역할        | Option A | Option B |
> |-------------|----------|----------|
> | Decision    | ?        | ?        |
> | Execution   | ?        | ?        |
> | Validation  | ?        | ?        |
> | Recovery    | ?        | ?        |
> ```

### Step 4 prompt — 예시 (scaffold)
> *"이 D/E/V/R 구조를 공유하는 3가지 사례: 1. {사례}, 2. {사례}, 3. {사례}. 와닿나요, 다른 거? (`skip`이면 건너뜀.)"*

### Step 5 prompt — Trade-off 확인
> *"Trade-off 초안: A는 {X} 얻고 {Y} 잃고; B는 {Y} 얻고 {X} 잃음. 너에게 의미 있는 비용 맞나요?"*

### Step 6 prompt — 강제 선택 (THE 게이트)
> *"표와 trade-off를 보고 **어느 쪽?** A 또는 B로 답하세요. '둘 다', '상황에 따라' 안 됩니다."*

### Step 7 prompt — 이해 검증 (scaffold)
> *"빠른 확인 (`skip`): 1. {X}는 무엇? 2. A/B 차이? 3. 각 옵션에서 누가 무엇?"*

### Step 8 prompt — 자산 기록 opt-in
> *"기본 태그: `{tag1},{tag2}`. 이 결정을 자산으로 기록할까요? (y / n / edit-tags)"*

## 사용자 응답 해석 규칙

모든 HITL 프롬프트에 적용.

**명확 (진행)**:
- `A` / `B` / `Option A` → 적절한 위치에서 선택 또는 확정
- 표 셀 직접 수정 / 명시적 덮어쓰기 → 그대로 사용
- `응 근데 X 바꿔` → 변경 적용 후 재확인

**모호 (재질문 필수)**:
- `응` / `그래` / `오케이` / `ㅇㅇ` / `Yeah` / `OK` → **확정 아님**. 해당 항목 다시 묻기.
- `둘 다` / `어느 쪽이든` / `상관없어` → Step 6에서 무효. 다시 진술: *"A 또는 B."*
- `상황에 따라` → 묻기: *"어떤 상황?"* — 그게 Step 1 입력.
- `네가 골라` / `알아서 해줘` → 답: *"forki는 너 대신 결정할 수 없습니다. A 또는 B를 선택하세요."*
- `몰라` / `I don't know` (Step 3 셀) → 묻기: *"답이 '아무도 없음'인가요, 더 생각해봐야 하나요?"* — `아무도 없음` 또는 이름이 나올 때만 진행.
- 침묵 / 무관한 응답 → 같은 프롬프트 1회 반복. 2번 무시되면 종료: *"forki 일시정지. {항목}에 대한 입장이 생기면 재개하세요."*

**탈출 (종료)**:
- `그만` / `취소` → `forki aborted at Step {N}`로 종료.
- `다시` → Step 1로 복귀.

## 보고 포맷

### Default
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
{recorded | skipped (user opt-out) | not-persisted: no .harnish in CWD | record-failed: {짧은 사유}}
```

**Scaffold 생략시**: 섹션 본문 → `_skipped_`.

### Reused (Step 0 → trust)
```
## forki Decision (reused)
Source: .harnish/assets/decision-{date}.jsonl
Title: {title} | Date: {date}
```

### Aborted
```
## forki Decision (aborted)
At Step {N} — {사유: user stop / 2 ignored prompts / restart / could not converge after 3 back-jumps}.
마지막 확정: {요약}
```
