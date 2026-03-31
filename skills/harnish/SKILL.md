---
name: harnish
version: 0.0.1
description: >
  자율 구현 엔진. PRD를 태스크로 분해하고, RALP 루프(Read→Act→Log→Progress)로 자율 실행하며,
  세션 간 맥락을 유지하고, 경험을 축적한다.
  시딩(PRD→태스크), 구현 루프(RALP), 앵커링(세션 복원), 경험 축적(자산 감지·기록·압축·스킬화)의
  4개 축으로 동작한다. PROGRESS.json를 세션 간 영속 상태로 유지하여 세션이 바뀌어도
  작업 맥락을 잃지 않는다. 모든 종류의 PRD(drafti-architect/drafti-feature/수동 작성)에 대응한다.
  트리거: "구현 시작", "태스크 분해", "이 PRD로 작업해", "루프 돌려", "자율 실행",
  "다음 태스크", "이어서 진행", "진행 상태", "마일스톤 보고",
  "자산 현황", "자산 압축", "이 패턴 기억해", "스킬로 만들어",
  PROGRESS.json가 존재하고 사용자가 작업 재개를 요청할 때.
---

# harnish — 자율 구현 엔진

> 작업할수록 똑똑해지는 구현 환경.
> 실패가 가드레일이 되고, 패턴이 축적되며, 세션이 바뀌어도 맥락이 유실되지 않는다.

## 진입점 (START HERE)

```bash
HARNISH_ROOT="${CLAUDE_SKILL_DIR}/../.."
```

### 1. 환경 설정 (세션 시작 시 반드시 실행)

> bash 3.2+, python3, POSIX 유틸리티. macOS/Linux 모두 지원. GNU 전용 플래그 미사용.

```bash
HARNISH_ROOT="${CLAUDE_SKILL_DIR}/../.."
VALIDATE_SCRIPT="$HARNISH_ROOT/scripts/validate-progress.sh"
LOOP_STEP_SCRIPT="$HARNISH_ROOT/scripts/loop-step.sh"
CHECK_VIOL_SCRIPT="$HARNISH_ROOT/scripts/check-violations.sh"
COMPRESS_SCRIPT="$HARNISH_ROOT/scripts/compress-progress.sh"
REPORT_SCRIPT="$HARNISH_ROOT/scripts/progress-report.sh"

TASK_COMPLETE_COUNT=0
COMPRESS_EVERY_N=5

# CHECK_VIOL_SCRIPT: 세션 종료 시 또는 사용자 "위반 확인" 요청 시 사용
# bash "$CHECK_VIOL_SCRIPT" ./PROGRESS.json
```

### 2. 상태 확인 → 모드 라우팅

| 모드 | 트리거 | 읽을 reference |
|------|--------|---------------|
| **A: 시딩** | "구현 시작", "태스크 분해", PRD 제공 | `task-schema.md` + `progress-template.md` |
| **B: 구현 루프** | "이어서 진행", "루프 돌려", PROGRESS.json 존재 | `escalation-protocol.md` + `guardrail-levels.md` |
| **C: 경험** | "자산 현황", "압축", "기억해", "스킬로" | `thresholds.md` |

**규칙**: reference는 동시에 2개까지만 로드.

---

## 모드 A: 시딩 (PRD → 태스크)

1. PRD 파일 경로 확인: `docs/prd-{name}.md`
2. PRD §4, §6, §7 존재 여부 확인
3. 기존 자산 조회:
   ```bash
   bash "$HARNISH_ROOT/scripts/query-assets.sh" \
     --tags "{키}" --types guardrail --format text \
     --base-dir "$HARNISH_ROOT/_base/assets"
   ```
4. 페이즈 분할: 데이터 → 비즈니스 로직 → UI → 통합 테스트
5. 원자적 태스크 분해: **1 태스크 = 1파일 | 1함수 | 1테스트 | 1설정**
6. **`references/progress-template.md`를 읽고** 그 JSON 스키마대로 PROGRESS.json 생성 → 검증:
   ```bash
   bash "$VALIDATE_SCRIPT" ./PROGRESS.json
   ```
7. 사용자 검토 요청: "Phase {N}개, Task {M}개 시딩 완료 — 확인 후 '루프 돌려'"

상세: `references/task-schema.md`, `references/progress-template.md`

---

## 모드 B: 구현 루프 (RALP)

> **RALP = Read → Act → Log → Progress → repeat**
>
> 판단하지 않는다. 규칙을 따른다.
> 길을 잃으면 PROGRESS.json로 돌아온다.
> 막히면 에스컬레이션한다. 절대 혼자 발명하지 않는다.

### B.1 루프 진입

```bash
bash "$VALIDATE_SCRIPT" ./PROGRESS.json    # 구조 검증
bash "$LOOP_STEP_SCRIPT" ./PROGRESS.json   # 좌표 추출
# STATUS=ALL_DONE → 완료 보고
# STATUS=NO_DOING → 첫 Todo를 Doing으로 이동
# STATUS=ACTIVE   → 현재 Task + 다음 액션 확인
```

### B.2 전체 루프 흐름

```
[루프 진입] ←─────────────────────────────────────────────┐
      │                                                     │
      ├─ [READ]                                             │
      │    ├─ PROGRESS.json doing 객체 읽기                  │
      │    ├─ 현재 태스크 가이드(목적·전략·파일·참조)      │
      │    ├─ 금지사항·가드레일 읽기                       │
      │    └─ 자산 조회 (이전 경험 주입)                    │
      │         bash "$HARNISH_ROOT/scripts/query-assets.sh" \
      │           --tags "{task-id},{phase}" --format inject │
      │                                                     │
      ├─ [ACT]                                              │
      │    ├─ 가이드에 따라 파일 생성/수정                  │
      │    ├─ 금지사항 위반 → 즉시 STOP + 에스컬레이션     │
      │    └─ 가드레일 위반 → 경고 로그 + 자동 교정        │
      │                                                     │
      ├─ [LOG] (3액션마다)                                  │
      │    ├─ PROGRESS.json doing 갱신                        │
      │    │    현재 / 마지막 액션 / 다음 액션              │
      │    └─ bash "$VALIDATE_SCRIPT" ./PROGRESS.json         │
      │                                                     │
      └─ [PROGRESS]                                         │
           ├─ acceptance_criteria 실행 (§B.9)               │
           │    ├─ 통과                                     │
           │    │    ├─ Doing → Done 이동 (§B.4)            │
           │    │    ├─ 자산 기록 (pattern, 2회 실패→해결 시 failure)
           │    │    ├─ TASK_COMPLETE_COUNT += 1             │
           │    │    ├─ RAG 압축 판단 (§B.6)                │
           │    │    ├─ 다음 Todo → Doing 이동              │
           │    │    └─ goto [루프 진입] ───────────────────┘
           │    │
           │    └─ 실패
           │         ├─ 1-2회: 원인 분석 → 수정 → goto [ACT]
           │         ├─ 3회: failure 자산 기록 → 에스컬레이션
           │         └─ 자산 기록:
           │              bash "$HARNISH_ROOT/scripts/record-asset.sh" \
           │                --type failure --tags "{task-id},{phase}" \
           │                --title "실패: {요약}" \
           │                --content $'## 표면 증상\n{에러}\n## 실제 원인\n...'
           │
           └─ [마일스톤] Phase 내 모든 태스크 Done
                ├─ RAG 압축 (§B.6)
                ├─ 체크포인트 보고 (§B.5)
                └─ 사용자 응답 대기
                     ├─ "계속" → 다음 Phase → goto [루프 진입]
                     ├─ 피드백 → 수정 → 재보고
                     └─ 모든 Phase Done → 완료 보고
```

### B.3 Todo → Doing 이동 절차

```
1. PROGRESS.json .todo.phases[0].tasks[0] 확인 (첫 미완료 태스크)
2. depends_on 충족 확인 (선행 Task 모두 .done.phases에 존재)
3. PROGRESS.json 갱신:
   .doing.task = {id, title, started_at, current, next_action, blocker:null, retry_count:0, context}
   .todo.phases[0].tasks 에서 해당 task 제거 (tasks가 빈 배열이면 phases[0]도 제거)
4. .metadata.status 업데이트 (emoji, phase, task, label)
5. bash "$VALIDATE_SCRIPT" ./PROGRESS.json
```

### B.4 Doing → Done 전환 절차

```
1. .done.phases 에서 phase_num이 같은 Phase 찾기, 없으면 새 Phase 객체 추가:
   {phase: N, title: "...", compressed: false, tasks: []}
2. 완료 태스크를 해당 Phase의 .tasks 배열에 추가:
   {id, title, result: "1줄 요약", files_changed: [...], verification: "...", duration: "N턴"}
3. .doing.task = null
4. .metadata.last_session = ISO 8601 현재 시각
5. .stats.completed_tasks += 1
6. bash "$VALIDATE_SCRIPT" ./PROGRESS.json
```

### B.5 마일스톤 체크포인트 보고

```
✅ 마일스톤 도달: Phase {N} — {Phase 제목}

완료된 태스크 ({M}개):
  - Task {id}: {제목} → {핵심 결과}

변경된 파일 ({K}개):
  - {경로} (create/modify)

검증 결과: {acceptance_criteria 실행 결과}
다음 Phase 예정: Phase {N+1} — {제목}

계속 진행할까요?
```

사람이 읽을 수 있는 보고서가 필요할 때: `bash "$REPORT_SCRIPT" ./PROGRESS.json`

### B.6 RAG 압축 (Done 섹션 관리)

루프가 길어질수록 Done이 쌓여 컨텍스트 낭비. 두 가지 트리거:

```bash
# 마일스톤 기반 (권장) — Phase 완료 직후
bash "$COMPRESS_SCRIPT" ./PROGRESS.json --trigger milestone --phase {N}

# 카운터 기반 — N번째 태스크 완료마다
if (( TASK_COMPLETE_COUNT % COMPRESS_EVERY_N == 0 )); then
  bash "$COMPRESS_SCRIPT" ./PROGRESS.json --trigger count
fi
```

압축 후: Phase당 60줄 → 3줄 요약. 원본은 `.progress-archive/phases.jsonl`에 보존.

### B.7 가드레일 + 금지사항

**Soft (가드레일)** — 위반 시: 경고 + 자동 교정

```yaml
- 파일 하나에 변경이 100줄 초과 → 태스크 분할 검토
- 테스트 없이 구현 완료 선언 금지
- acceptance_criteria 없는 태스크 Done 처리 금지
- 현재 태스크 scope 외 파일 수정 시 경고
```

**Hard (금지사항)** — 위반 시: 즉시 STOP + 에스컬레이션

```yaml
- DROP TABLE / DROP DATABASE 실행 금지
- PRD에 명시되지 않은 새 패키지 설치 금지
- 하드코딩된 시크릿 삽입 금지
- scope 밖 파일의 비관련 리팩토링 금지
- PROGRESS.json 삭제 또는 done 객체 직접 수정 금지
```

### B.8 에스컬레이션

| 실패 횟수 | 동작 |
|----------|------|
| 1회 | 원인 분석 → 다른 방법으로 재시도 |
| 2회 | 원인 기록 후 재시도. 해결 시 failure 자산 기록 |
| 3회 | **에스컬레이션** — 혼자 해결하지 않는다 |

보고 형식:
```
🆘 에스컬레이션: Task {ID} — {제목}

막힌 지점: {구체적 파일/함수/명령}
시도한 것:
  1. {시도 1}: {결과}
  2. {시도 2}: {결과}
  3. {시도 3}: {결과}

제안하는 선택지:
  A. {선택지 A}
  B. {선택지 B}
```

상세: `references/escalation-protocol.md`, `references/guardrail-levels.md`

### B.9 acceptance_criteria 실행 방법

| criteria 형태 | 실행 방법 | 통과 기준 |
|--------------|----------|----------|
| **bash 명령** | 그대로 실행 | exit code 0 |
| **조건 목록** | 코드베이스에서 각 조건 충족 확인 | 모든 항목 ✓ |
| **혼합** | bash 먼저, 조건은 이후 | 둘 다 통과 |
| **없음** | 에스컬레이션 (criteria 없이 Done 금지) | — |

```
IF criteria에 bash 명령 포함:
  → 실행 → exit code 기록
  → 0이면 통과, 아니면 실패 (에러 메시지 보존)

IF criteria에 조건 목록 포함:
  → 각 조건을 코드/파일에서 직접 확인
  → "파일 존재" → ls -la
  → "함수 정의" → grep
  → "타입 에러 없음" → 프로젝트 언어에 맞는 타입 체커 실행
     (Python: mypy, TS: tsc --noEmit, Go: go vet, Java: javac, Rust: cargo check)

IF criteria가 비어있음:
  → Done 처리 금지 → 에스컬레이션
```

---

## 모드 C: 경험 축적 (앵커링 포함)

### 앵커링 (세션 복원)

세션 시작 시:
1. `bash "$VALIDATE_SCRIPT" ./PROGRESS.json` → 구조 정상 확인
2. `bash "$LOOP_STEP_SCRIPT" ./PROGRESS.json` → 좌표 추출
3. Doing 있으면 "다음 액션"부터 재개 / 없으면 Todo 첫 Task
4. 상태 보고:
   ```
   🔄 세션 복원 완료
   현재 위치: Phase {N} / Task {ID} — {제목}
   다음 액션: {next_action}
   재개합니다.
   ```

### 자산 유형

| 유형 | 폴더 | 감지 기준 |
|------|------|---------|
| failure | failures/ | 동일 에러 2회+ 발생 후 해결 |
| pattern | patterns/ | 첫 시도 성공 + 재사용 가능 |
| guardrail | guardrails/ | 명시적 제약 선언 또는 부작용 발견 |
| snippet | snippets/ | 동일 코드 구조 2회+ 작성 |
| decision | decisions/ | A vs B 선택 + 근거 존재 |

### 기록 판단 규칙

```
IF 동일 에러 2회+ AND 해결됨 → failure 기록 (필수)
IF 사용자 "기억해/패턴 기록" → 해당 유형 기록 (필수)
IF 사용자 "절대 ~하지 마" → guardrail 기록 (필수)
IF 첫 시도 성공 AND 범용적 → pattern 기록 (권장)
IF A vs B 선택 AND 근거 명확 → decision 기록 (권장)
IF 동일 코드 구조 2회+ → snippet 기록 (권장)
ELSE → 기록하지 않음
```

### 조회/압축/스킬화

```bash
# 조회
bash "$HARNISH_ROOT/scripts/query-assets.sh" --tags "docker,cache" --format inject --base-dir "$HARNISH_ROOT/_base/assets"

# 현황
bash "$HARNISH_ROOT/scripts/check-thresholds.sh" --base-dir "$HARNISH_ROOT/_base/assets"

# 압축 (동일 태그 5건+)
bash "$HARNISH_ROOT/scripts/compress-assets.sh" --tag docker --base-dir "$HARNISH_ROOT/_base/assets"

# 스킬 초안
bash "$HARNISH_ROOT/scripts/skillify.sh" --source "$HARNISH_ROOT/_base/assets/.compressed/{file}.md" --skill-name docker-patterns

# 품질 게이트
bash "$HARNISH_ROOT/scripts/quality-gate.sh" --base-dir "$HARNISH_ROOT/_base/assets"
```

### 수동 트리거

| 발화 | 동작 |
|------|------|
| "자산 현황" | check-thresholds.sh |
| "자산 압축" | compress-assets.sh |
| "이 패턴 기억해" | record-asset.sh (pattern) |
| "스킬로 만들어" | skillify.sh |
| "자산 품질" | quality-gate.sh |
| "위반 확인" | check-violations.sh |

---

## 결정표

| 상황 | 동작 |
|------|------|
| PRD만 존재, PROGRESS.json 없음 | 모드 A (시딩) |
| PROGRESS.json 존재, Doing 있음 | 모드 B ("다음 액션"부터) |
| PROGRESS.json 존재, Doing 없고 Todo 있음 | 첫 Todo → Doing → 모드 B |
| 모든 태스크 Done | 완료 보고 |
| 자산 관련 요청 | 모드 C |
| acceptance_criteria 없음 | 에스컬레이션 |
| 금지사항 위반 | 즉시 STOP + 에스컬레이션 |
| 3회 실패 | failure 기록 + 에스컬레이션 |
| 다음에 뭘 해야 할지 모를 때 | PROGRESS.json로 돌아가기 (절대 발명 금지) |

## 체크포인트 규칙

- **매 3액션**: PROGRESS.json 갱신 (현재/마지막/다음)
- **Task 완료**: Doing → Done, 완료 시간, 변경 파일, 검증 결과
- **Phase 완료**: 마일스톤 보고, RAG 압축, 사용자 승인
- **세션 종료**: 품질 게이트 (오늘 자산 완성도 1회 스캔) + 위반 확인 (`bash "$CHECK_VIOL_SCRIPT" ./PROGRESS.json`)

## 종료 조건

- Todo 비어있고 Doing 비어있음 → STOP
- 사용자 "중단" → PROGRESS.json에 현재 상태 기록 후 STOP

## 맥락 예산

| 모드 | 읽는 reference | 예상 토큰 |
|------|---------------|----------|
| 시딩 | task-schema.md + progress-template.md | ~8K |
| 구현 | escalation-protocol.md + guardrail-levels.md | ~6K |
| 경험 | thresholds.md | ~3K |

동시 로드 최대 2개. 이전 reference가 컨텍스트에 남는 것은 감수.
