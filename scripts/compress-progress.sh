#!/usr/bin/env bash
# compress-progress.sh — PROGRESS.json Done 섹션 압축 + JSONL 아카이브
#
# 역할:
#   완료된 Phase를 PROGRESS.json에서 compressed stub으로 축약하고,
#   상세 내용은 .progress-archive/phases.jsonl 에 한 줄(JSON)로 저장한다.
#
# 트리거:
#   A. milestone: Phase 완료 직후 — 해당 Phase를 정확히 압축
#      bash compress-progress.sh ./PROGRESS.json --trigger milestone --phase 1
#
#   B. count: 카운터 기반 — Done에 미압축 완료 Phase가 있으면 압축
#      bash compress-progress.sh ./PROGRESS.json --trigger count
#
# 옵션:
#   --trigger milestone|count
#   --phase N             압축할 Phase 번호 (milestone 트리거 시 필수)
#   --dry-run             실제 변경 없이 출력만

set -euo pipefail

PROGRESS_FILE="${1:-./PROGRESS.json}"
TRIGGER="count"
TARGET_PHASE=""
DRY_RUN=false

# ── 의존성 체크 ──
if ! command -v jq &>/dev/null; then
    echo "오류: jq가 설치되어 있지 않습니다. brew install jq" >&2
    exit 1
fi

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger)   TRIGGER="$2";    shift 2 ;;
    --phase)     TARGET_PHASE="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true;    shift   ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "ERROR: $PROGRESS_FILE 없음" >&2; exit 1
fi

if ! jq empty "$PROGRESS_FILE" 2>/dev/null; then
  echo "ERROR: 유효한 JSON이 아닙니다: $PROGRESS_FILE" >&2; exit 1
fi

if [[ "$TRIGGER" == "milestone" && -z "$TARGET_PHASE" ]]; then
  echo "ERROR: --trigger milestone 사용 시 --phase N 필요" >&2; exit 1
fi

PROGRESS_DIR="$(dirname "$PROGRESS_FILE")"
ARCHIVE_DIR="${PROGRESS_DIR}/.progress-archive"
ARCHIVE_JSONL="${ARCHIVE_DIR}/phases.jsonl"

# ── 압축할 Phase 목록 결정 ──
PHASES_TO_COMPRESS=()
if [[ "$TRIGGER" == "milestone" ]]; then
  PHASES_TO_COMPRESS=("$TARGET_PHASE")
else
  while IFS= read -r phase_num; do
    [[ -n "$phase_num" ]] && PHASES_TO_COMPRESS+=("$phase_num")
  done < <(jq -r '.done.phases[] | select(.compressed != true) | .phase' "$PROGRESS_FILE" 2>/dev/null || true)
fi

if [[ ${#PHASES_TO_COMPRESS[@]} -eq 0 ]]; then
  echo "ℹ️  압축할 Phase 없음"; exit 0
fi

echo "🗜  압축 대상 Phase: ${PHASES_TO_COMPRESS[*]}"

# ── 아카이브 디렉토리 + 백업 ──
[[ "$DRY_RUN" == false ]] && mkdir -p "$ARCHIVE_DIR"
[[ "$DRY_RUN" == false ]] && cp "$PROGRESS_FILE" "${PROGRESS_FILE}.backup"

CURRENT_JSON=$(cat "$PROGRESS_FILE")

for PHASE_NUM in "${PHASES_TO_COMPRESS[@]}"; do
  # Phase 데이터 존재 확인
  PHASE_EXISTS=$(echo "$CURRENT_JSON" | jq --argjson p "$PHASE_NUM" \
    '[.done.phases[] | select(.phase == $p and .compressed != true)] | length')

  if [[ "$PHASE_EXISTS" -eq 0 ]]; then
    echo "  Phase ${PHASE_NUM}: 미압축 블록 없음 — 건너뜀"; continue
  fi

  # Phase 메타데이터 추출
  PHASE_DATA=$(echo "$CURRENT_JSON" | jq --argjson p "$PHASE_NUM" \
    '.done.phases[] | select(.phase == $p and .compressed != true)')

  PHASE_TITLE=$(echo "$PHASE_DATA" | jq -r '.title // "Phase"')
  TASK_COUNT=$(echo "$PHASE_DATA" | jq '[.tasks[]] | length')
  TASK_IDS=$(echo "$PHASE_DATA" | jq -r '[.tasks[].id] | join(",")')
  CHANGED_FILES=$(echo "$PHASE_DATA" | jq -r '[.tasks[].files_changed[] // empty] | unique | join(",")')
  COMPRESSED_AT="$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

  # JSONL 레코드 생성
  JSON_RECORD=$(echo "$PHASE_DATA" | jq -c --arg at "$COMPRESSED_AT" '{
    phase: .phase,
    title: .title,
    compressed_at: $at,
    tasks_completed: (.tasks | length),
    task_ids: [.tasks[].id],
    files_changed: [.tasks[].files_changed[] // empty] | unique,
    milestone_approved_at: .milestone_approved_at
  }')

  if [[ "$DRY_RUN" == true ]]; then
    echo "  [dry-run] JSONL 레코드: ${JSON_RECORD}"
  else
    echo "${JSON_RECORD}" >> "$ARCHIVE_JSONL"
    echo "  ✅ Phase ${PHASE_NUM} → ${ARCHIVE_JSONL} 에 append"
  fi

  # PROGRESS.json에서 Phase를 compressed stub으로 교체
  SUMMARY_LINE="tasks:${TASK_COUNT} | files:${CHANGED_FILES:-없음}"
  ARCHIVE_REF=".progress-archive/phases.jsonl#phase=${PHASE_NUM}"

  CURRENT_JSON=$(echo "$CURRENT_JSON" | jq --argjson p "$PHASE_NUM" \
    --arg summary "$SUMMARY_LINE" \
    --arg ref "$ARCHIVE_REF" \
    '(.done.phases |= [.[] | if .phase == $p and .compressed != true then
      {phase: .phase, title: .title, compressed: true, compressed_summary: $summary, archive_ref: $ref}
    else . end])')
done

# ── 변경 적용 ──
if [[ "$DRY_RUN" == false ]]; then
  echo "$CURRENT_JSON" > "${PROGRESS_FILE}.tmp" && mv "${PROGRESS_FILE}.tmp" "$PROGRESS_FILE"

  echo ""
  echo "🗜  압축 완료"
  echo "   아카이브: ${ARCHIVE_JSONL}"
  echo "   백업: ${PROGRESS_FILE}.backup"
  [[ -f "$ARCHIVE_JSONL" ]] && echo "   누적 레코드: $(wc -l < "$ARCHIVE_JSONL" | tr -d ' ')개 Phase"
else
  echo "[dry-run] 실제 변경 없음"
fi
