#!/usr/bin/env bash
# compress-progress.sh — PROGRESS.md Done 섹션 압축 + JSONL 아카이브
#
# 역할:
#   완료된 Phase를 PROGRESS.md에서 3줄 요약으로 축약하고,
#   상세 내용은 .progress-archive/phases.jsonl 에 한 줄(JSON)로 저장한다.
#   LLM이 읽는 아카이브이므로 .md 대신 토큰 효율적인 JSONL을 사용한다.
#
# 아카이브 포맷 (phases.jsonl — Phase 완료마다 1줄 append):
#   {"phase":1,"title":"데이터 모델","compressed_at":"...","tasks":4,
#    "files":["schema.prisma","migrations/001.sql"],
#    "decisions":["cuid for IDs"],"patterns":["prisma validate flow"],
#    "guardrail_hits":0,"failure_count":1,"task_ids":["1-1","1-2","1-3","1-4"]}
#
# 플랫폼: bash 3.2+, python3, POSIX 유틸리티 (macOS/Linux 호환)
#
# 트리거:
#   A. milestone: Phase 완료 직후 — 해당 Phase를 정확히 압축
#      bash compress-progress.sh ./PROGRESS.md --trigger milestone --phase 1
#
#   B. count: 카운터/루프 기반 — Done에 미압축 완료 Phase가 있으면 압축, 없으면 no-op
#      bash compress-progress.sh ./PROGRESS.md --trigger count
#
# 옵션:
#   --trigger milestone|count
#   --phase N             압축할 Phase 번호 (milestone 트리거 시 필수)
#   --dry-run             실제 변경 없이 출력만
#
# 종료 코드:
#   0 — 압축 완료 또는 압축 대상 없음 (정상)
#   1 — 오류

set -euo pipefail

PROGRESS_FILE="${1:-./PROGRESS.md}"
TRIGGER="count"
TARGET_PHASE=""
DRY_RUN=false
TEMP_FILE=""

# ── 임시 파일 클린업 trap ──
cleanup() { [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"; }
trap cleanup EXIT

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger)   TRIGGER="$2";    shift 2 ;;
    --phase)     TARGET_PHASE="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true;    shift   ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

# ────────────────────────────────────────
# 파일 존재 + python3 확인
# ────────────────────────────────────────
if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "ERROR: $PROGRESS_FILE 없음" >&2; exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 필요 — 압축 기능은 python3에 의존합니다" >&2; exit 1
fi

PROGRESS_DIR="$(dirname "$PROGRESS_FILE")"
ARCHIVE_DIR="${PROGRESS_DIR}/.progress-archive"
ARCHIVE_JSONL="${ARCHIVE_DIR}/phases.jsonl"

# ────────────────────────────────────────
# Done 섹션 추출 (POSIX 호환: head -n -1 대신 sed 사용)
# ────────────────────────────────────────
DONE_SECTION=$(awk '/^## ✅ 완료 \(Done\)/,/^## 🔨 진행 중/' "$PROGRESS_FILE" \
  | sed '$d' 2>/dev/null || true)

# ────────────────────────────────────────
# milestone 트리거: --phase 필수
# ────────────────────────────────────────
if [[ "$TRIGGER" == "milestone" && -z "$TARGET_PHASE" ]]; then
  echo "ERROR: --trigger milestone 사용 시 --phase N 필요" >&2; exit 1
fi

# ────────────────────────────────────────
# 압축할 Phase 목록 결정
# POSIX 호환: mapfile 대신 while-read, grep -P 대신 grep -E + sed
# ────────────────────────────────────────
PHASES_TO_COMPRESS=()
if [[ "$TRIGGER" == "milestone" ]]; then
  PHASES_TO_COMPRESS=("$TARGET_PHASE")
else
  # count 트리거: Done 섹션에서 아직 압축되지 않은 Phase 전체
  while IFS= read -r phase_num; do
    [[ -n "$phase_num" ]] && PHASES_TO_COMPRESS+=("$phase_num")
  done < <(
    echo "$DONE_SECTION" \
      | grep -E '^### Phase [0-9]+' \
      | grep -v '✅ \[압축됨\]' \
      | sed -n 's/^### Phase \([0-9]*\).*/\1/p' \
      | sort -nu 2>/dev/null || true
  )
fi

if [[ ${#PHASES_TO_COMPRESS[@]} -eq 0 ]]; then
  echo "ℹ️  압축할 Phase 없음"; exit 0
fi

echo "🗜  압축 대상 Phase: ${PHASES_TO_COMPRESS[*]}"

# ────────────────────────────────────────
# 아카이브 디렉토리 생성
# ────────────────────────────────────────
[[ "$DRY_RUN" == false ]] && mkdir -p "$ARCHIVE_DIR"

# ────────────────────────────────────────
# PROGRESS.md 백업 + 임시 복사
# ────────────────────────────────────────
TEMP_FILE="${PROGRESS_FILE}.compress.$$"
if [[ "$DRY_RUN" == false ]]; then
  cp "$PROGRESS_FILE" "${PROGRESS_FILE}.backup"
fi
cp "$PROGRESS_FILE" "$TEMP_FILE"

# ────────────────────────────────────────
# Phase별 처리
# ────────────────────────────────────────
for PHASE_NUM in "${PHASES_TO_COMPRESS[@]}"; do

  # Phase 블록 추출 — Done 섹션 내에서만, flag 기반 (awk range start=end 버그 회피)
  # 이유: awk range '/^### Phase 1/,/^### Phase [0-9]/' 에서 시작 패턴이 종료 패턴에도
  #       매칭되어 한 줄만 추출되는 문제가 있음
  PHASE_BLOCK=$(echo "$DONE_SECTION" | awk -v pstart="^### Phase ${PHASE_NUM}[: ]" '
    $0 ~ pstart { found=1 }
    found && /^### Phase [0-9]/ && !($0 ~ pstart) { exit }
    found
  ')

  if [[ -z "$PHASE_BLOCK" ]]; then
    echo "  Phase ${PHASE_NUM}: 블록 없음 — 건너뜀"; continue
  fi

  # ── 메타 추출 (POSIX 호환: grep -oP → grep -oE / sed) ──
  PHASE_TITLE=$(echo "$PHASE_BLOCK" | grep "^### Phase ${PHASE_NUM}" | \
    sed "s/^### Phase ${PHASE_NUM}[: ]*//" | head -1 || echo "Phase ${PHASE_NUM}")

  TASK_IDS=$(echo "$PHASE_BLOCK" | grep -oE 'Task [0-9]+-[0-9]+' | \
    sed 's/^Task //' | sort -V | paste -sd',' || echo "")
  TASK_COUNT=$(echo "$PHASE_BLOCK" | grep -c '^\- \[x\]' 2>/dev/null || true)

  CHANGED_FILES=$(echo "$PHASE_BLOCK" | grep '변경 파일:' | \
    sed 's/.*변경 파일: //' | tr ', ' '\n' | grep -v '^$' | \
    sort -u | paste -sd',' || echo "")

  DECISIONS=$(echo "$PHASE_BLOCK" | grep -iE '결정:|→ 결정|선택:' | \
    sed 's/.*결정[: ]//' | sed 's/.*→ 결정 //' | head -5 | \
    paste -sd',' || echo "")

  PATTERNS=$(echo "$PHASE_BLOCK" | grep -iE '패턴:|pattern:' | \
    sed 's/.*패턴[: ]*//' | head -3 | paste -sd',' || echo "")

  GUARDRAIL_HITS=$(echo "$PHASE_BLOCK" | grep -c '⚠️\|가드레일\|경고' 2>/dev/null || true)
  FAILURE_COUNT=$(echo "$PHASE_BLOCK" | grep -c '❌\|실패\|retry' 2>/dev/null || true)

  COMPRESSED_AT="$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

  # ── JSONL 레코드 생성 (환경변수로 전달 — heredoc injection 방지) ──
  JSON_RECORD=$(
    CP_PHASE_NUM="$PHASE_NUM" \
    CP_PHASE_TITLE="$PHASE_TITLE" \
    CP_COMPRESSED_AT="$COMPRESSED_AT" \
    CP_TASK_COUNT="$TASK_COUNT" \
    CP_TASK_IDS="$TASK_IDS" \
    CP_CHANGED_FILES="$CHANGED_FILES" \
    CP_DECISIONS="$DECISIONS" \
    CP_PATTERNS="$PATTERNS" \
    CP_GUARDRAIL_HITS="$GUARDRAIL_HITS" \
    CP_FAILURE_COUNT="$FAILURE_COUNT" \
    python3 -c '
import json, os

def split_csv(s):
    return [x.strip() for x in s.split(",") if x.strip()] if s else []

record = {
    "phase": int(os.environ["CP_PHASE_NUM"]),
    "title": os.environ["CP_PHASE_TITLE"],
    "compressed_at": os.environ["CP_COMPRESSED_AT"],
    "tasks_completed": int(os.environ["CP_TASK_COUNT"]),
    "task_ids": split_csv(os.environ["CP_TASK_IDS"]),
    "files_changed": split_csv(os.environ["CP_CHANGED_FILES"]),
    "key_decisions": split_csv(os.environ["CP_DECISIONS"]),
    "patterns": split_csv(os.environ["CP_PATTERNS"]),
    "guardrail_hits": int(os.environ["CP_GUARDRAIL_HITS"]),
    "failure_count": int(os.environ["CP_FAILURE_COUNT"]),
}
print(json.dumps(record, ensure_ascii=False))
'
  )

  # ── JSONL append ──
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [dry-run] JSONL 레코드:"
    echo "  ${JSON_RECORD}"
  else
    echo "${JSON_RECORD}" >> "$ARCHIVE_JSONL"
    echo "  ✅ Phase ${PHASE_NUM} → ${ARCHIVE_JSONL} 에 append"
  fi

  # ── PROGRESS.md에서 Phase 블록을 3줄 요약으로 교체 (환경변수로 전달) ──
  SUMMARY="### Phase ${PHASE_NUM}: ${PHASE_TITLE} ✅ [압축됨]
- tasks:${TASK_COUNT} | files:${CHANGED_FILES:-없음}
- archive: .progress-archive/phases.jsonl#phase=${PHASE_NUM}"

  if [[ "$DRY_RUN" == false ]]; then
    CP_TEMP_FILE="$TEMP_FILE" \
    CP_PHASE_NUM="$PHASE_NUM" \
    CP_SUMMARY="$SUMMARY" \
    python3 -c '
import re, os

temp_file = os.environ["CP_TEMP_FILE"]
phase_num = os.environ["CP_PHASE_NUM"]
summary = os.environ["CP_SUMMARY"]

with open(temp_file, "r") as f:
    content = f.read()

pattern = r"### Phase " + re.escape(phase_num) + r"[:\s][^\n]*\n.*?(?=### Phase \d|## |\Z)"
replacement = summary + "\n\n"

new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

with open(temp_file, "w") as f:
    f.write(new_content)
'
  fi

done

# ────────────────────────────────────────
# 변경 적용
# ────────────────────────────────────────
if [[ "$DRY_RUN" == false ]]; then
  mv "$TEMP_FILE" "$PROGRESS_FILE"
  TEMP_FILE=""  # trap이 이미 이동된 파일을 삭제하지 않도록

  NEW_LINES=$(wc -l < "$PROGRESS_FILE" | tr -d ' ')
  echo ""
  echo "🗜  압축 완료"
  echo "   PROGRESS.md: ${NEW_LINES}줄"
  echo "   아카이브: ${ARCHIVE_JSONL}"
  echo "   백업: ${PROGRESS_FILE}.backup"
  [[ -f "$ARCHIVE_JSONL" ]] && echo "   누적 레코드: $(wc -l < "$ARCHIVE_JSONL")개 Phase"
else
  echo "[dry-run] 실제 변경 없음"
fi
