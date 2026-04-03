---
name: harnish
version: 0.0.1
description: >
  자율 구현 엔진. PRD→태스크 분해, RALP 루프 자율 실행, 세션 간 맥락 유지, 경험 축적.
  트리거: "구현 시작", "태스크 분해", "루프 돌려", "이어서 진행",
  "다음 태스크", "진행 상태", "자산 현황", "자산 압축",
  "이 패턴 기억해", "스킬로 만들어",
  harnish-current-work.json 존재 시 작업 재개 요청.
---

# harnish — 자율 구현 엔진

> 판단하지 않는다. 규칙을 따른다. 길을 잃으면 harnish-current-work.json로 돌아온다. 막히면 에스컬레이션한다. 발명 금지.

## 스킬 체인

```
drafti-architect (또는 drafti-feature) → harnish → ralpi
```

| 스킬 | 독립 호출 | 전제 조건 |
|------|----------|----------|
| drafti-architect | 가능 | 없음 (기술 문제만 있으면 됨) |
| drafti-feature | 가능 | 기획서 필요 |
| harnish | 가능 | docs/prd-*.md 또는 기존 harnish-current-work.json |
| ralpi | 가능 | 검증 대상 파일/디렉토리 지정 |

harnish 시작 시 PRD 없으면: "PRD가 없습니다. /drafti-architect 또는 /drafti-feature로 먼저 생성하세요."

## 환경 설정 (세션 시작 시 실행)

> bash 3.2+, python3, jq. macOS/Linux.

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
VALIDATE_SCRIPT="$HARNISH_ROOT/scripts/validate-progress.sh"
LOOP_STEP_SCRIPT="$HARNISH_ROOT/scripts/loop-step.sh"
CHECK_VIOL_SCRIPT="$HARNISH_ROOT/scripts/check-violations.sh"
COMPRESS_SCRIPT="$HARNISH_ROOT/scripts/compress-progress.sh"
REPORT_SCRIPT="$HARNISH_ROOT/scripts/progress-report.sh"
TASK_COMPLETE_COUNT=0
COMPRESS_EVERY_N=5
```

## Step 1: 모드 판별

| 조건 | 모드 | 다음 | 읽을 reference |
|------|------|------|---------------|
| PRD 제공, harnish-current-work.json 없음 | 시딩 | Step 2 | `task-schema.md` + `progress-template.md` |
| harnish-current-work.json 존재 | 구현 루프 | Step 3 | `escalation-protocol.md` + `guardrail-levels.md` |
| "자산 현황/압축/기억해/스킬로" | 경험 | Step 5 | `thresholds.md` |
| harnish-current-work.json 존재 + 세션 시작 | 복원 | Step 4 | — |

reference는 **동시에 2개까지만** 로드.

## Step 2: 시딩 (PRD → harnish-current-work.json)

1. PRD 파일 확인: `docs/prd-{name}.md`. §4(구현명세), §6(테스트), §7(가드레일) 존재 확인
2. 기존 자산 조회:
   ```bash
   bash "$HARNISH_ROOT/scripts/query-assets.sh" \
     --tags "{키}" --types guardrail --format text \
     --base-dir "$(pwd)/.harnish"
   ```
3. 페이즈 분할: 데이터 → 비즈니스 로직 → UI → 통합 테스트
4. 태스크 분해: **1 태스크 = 1파일 | 1함수 | 1테스트 | 1설정**
5. `references/progress-template.md`를 읽고 harnish-current-work.json 생성 → 검증:
   ```bash
   bash "$VALIDATE_SCRIPT" .harnish/harnish-current-work.json
   ```
6. 사용자에게 보고: "Phase {N}개, Task {M}개 시딩 완료 — 확인 후 '루프 돌려'"
7. → Step 3으로

## Step 3: 구현 루프 (RALP)

### 진입

```bash
bash "$VALIDATE_SCRIPT" .harnish/harnish-current-work.json
bash "$LOOP_STEP_SCRIPT" .harnish/harnish-current-work.json
```
- `STATUS=ALL_DONE` → 완료 보고 → STOP
- `STATUS=NO_DOING` → 첫 Todo를 Doing으로 이동 (아래 "Todo→Doing" 참조)
- `STATUS=ACTIVE` → 현재 태스크의 다음 액션 확인 → 루프 시작

### 루프 1회 = READ → ACT → LOG → PROGRESS

**[READ]**
- harnish-current-work.json doing 태스크의 목적·전략·파일·금지사항 읽기
- 자산 조회: `bash "$HARNISH_ROOT/scripts/query-assets.sh" --tags "{task-id},{phase}" --format inject --base-dir "$(pwd)/.harnish"`

**[ACT]**
- 가이드에 따라 파일 생성/수정
- Hard 가드레일 위반 → 즉시 STOP + 에스컬레이션
- Soft 가드레일 위반 → 경고 + 자동 교정

**[LOG]** (3액션마다)
- harnish-current-work.json doing 갱신: 현재 / 마지막 액션 / 다음 액션
- `bash "$VALIDATE_SCRIPT" .harnish/harnish-current-work.json`

**[PROGRESS]** acceptance_criteria 실행:
- **통과** → Doing→Done 이동 → 자산 기록(해당 시) → TASK_COMPLETE_COUNT += 1 → 다음 Todo→Doing → 루프 반복
- **1~2회 실패** → 원인 분석 → 수정 → [ACT]로
- **3회 실패** → failure 자산 기록 → **에스컬레이션. 혼자 해결 금지.**

### acceptance_criteria 실행 방법

| 형태 | 실행 | 통과 기준 |
|------|------|----------|
| bash 명령 | 그대로 실행 | exit 0 |
| 조건 목록 | 코드에서 각 조건 확인 | 모두 ✓ |
| 혼합 | bash 먼저, 조건은 이후 | 둘 다 통과 |
| 없음 | **에스컬레이션** (criteria 없이 Done 금지) | — |

#### acceptance_criteria 비어있을 때 동작 시점

1. **시딩 (Step 2)**: PRD §6에서 criteria 추출. 매핑 불가 시 → 사용자에게 즉시 질문: "Task {id}의 acceptance_criteria를 지정해주세요."
2. **Todo→Doing 이동 시**: acceptance_criteria 필드가 비어있거나 없으면 → Doing 전환 전 에스컬레이션. Doing으로 넘기지 않음.
3. **[PROGRESS] 단계**: Doing 상태에서 criteria가 비어있으면 → 즉시 에스컬레이션 (1회 시도도 하지 않음). 3회 실패 규칙과 별개.

### Todo→Doing 이동

1. `.todo.phases[0].tasks[0]` 확인 (첫 미완료 태스크)
2. `depends_on` 충족 확인 (선행 Task 모두 `.done.phases`에 존재)
3. harnish-current-work.json 갱신: `.doing.task = {id, title, started_at, current, next_action, blocker:null, retry_count:0, context}`, `.todo`에서 해당 task 제거
4. `.metadata.status` 업데이트
5. `bash "$VALIDATE_SCRIPT" .harnish/harnish-current-work.json`

### Doing→Done 이동

1. `.done.phases`에서 같은 phase 찾기 (없으면 새 Phase 추가)
2. 완료 태스크 추가: `{id, title, result: "1줄 요약", files_changed, verification, duration}`
3. `.doing.task = null`, `.stats.completed_tasks += 1`
4. `bash "$VALIDATE_SCRIPT" .harnish/harnish-current-work.json`

### Phase 완료 시 (마일스톤)

```
✅ 마일스톤: Phase {N} — {제목}
완료: {M}개 태스크 / 변경: {K}개 파일
다음: Phase {N+1} — 계속 진행할까요?
```

RAG 압축 실행:
```bash
bash "$COMPRESS_SCRIPT" .harnish/harnish-current-work.json --trigger milestone --phase {N}
```

카운터 기반 압축 (COMPRESS_EVERY_N 마다):
```bash
if (( TASK_COMPLETE_COUNT % COMPRESS_EVERY_N == 0 )); then
  bash "$COMPRESS_SCRIPT" .harnish/harnish-current-work.json --trigger count
fi
```

사용자 응답 대기 → "계속" → 다음 Phase → 루프 반복. 모든 Phase Done → 완료 보고.

### 에스컬레이션 보고

```
🆘 에스컬레이션: Task {ID} — {제목}
막힌 지점: {파일/함수/명령}
시도: 1. {시도}: {결과} / 2. ... / 3. ...
선택지: A. {A} / B. {B}
```

## Step 4: 세션 복원 (앵커링)

harnish-current-work.json 존재 + 새 세션 시작 시:

1. `bash "$VALIDATE_SCRIPT" .harnish/harnish-current-work.json` → 구조 정상 확인
2. `bash "$LOOP_STEP_SCRIPT" .harnish/harnish-current-work.json` → 좌표 추출
3. Doing 있으면 "다음 액션"부터 재개 / 없으면 Todo 첫 Task
4. 보고 후 → Step 3 루프 진입:
   ```
   🔄 세션 복원 완료
   현재: Phase {N} / Task {ID} — {제목}
   다음: {next_action}
   ```

## Step 5: 경험 축적

### 자산 기록 판단

| 조건 | 유형 | 필수/권장 |
|------|------|----------|
| 동일 에러 2회+ AND 해결 | failure | 필수 |
| 사용자 "기억해/패턴 기록" | 해당 유형 | 필수 |
| 사용자 "절대 ~하지 마" | guardrail | 필수 |
| 첫 시도 성공 AND 범용적 | pattern | 권장 |
| A vs B 선택 AND 근거 명확 | decision | 권장 |
| 동일 코드 구조 2회+ | snippet | 권장 |
| 위 해당 없음 | — | 기록하지 않음 |

기록:
```bash
bash "$HARNISH_ROOT/scripts/record-asset.sh" \
  --type {유형} --tags "{task-id},{phase}" \
  --title "{한 줄}" --content "{내용}" \
  --base-dir "$(pwd)/.harnish"
```

### 수동 트리거

| 발화 | 스크립트 |
|------|---------|
| "자산 현황" | check-thresholds.sh |
| "자산 압축" | compress-assets.sh |
| "이 패턴 기억해" | record-asset.sh --type pattern |
| "스킬로 만들어" | skillify.sh |
| "자산 품질" | quality-gate.sh |
| "위반 확인" | check-violations.sh |

## 가드레일

**Soft** (경고 + 교정):
- 파일 100줄+ 변경 → 태스크 분할 검토
- 테스트 없이 Done 선언 금지
- acceptance_criteria 없는 태스크 Done 처리 금지
- 현재 태스크 scope 외 파일 수정 시 경고

**Hard** (즉시 STOP + 에스컬레이션):
- DROP TABLE / DROP DATABASE 금지
- PRD에 명시되지 않은 새 패키지 설치 금지
- 하드코딩된 시크릿 삽입 금지
- scope 밖 파일의 비관련 리팩토링 금지
- harnish-current-work.json 삭제 또는 done 객체 직접 수정 금지

## 종료 조건

- Todo 비어있고 Doing 없음 → 완료 보고 → STOP
- 사용자 "중단" → harnish-current-work.json에 현재 상태 기록 → STOP
- 세션 종료 시 → `bash "$CHECK_VIOL_SCRIPT" .harnish/harnish-current-work.json`
