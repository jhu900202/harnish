#!/usr/bin/env bash
# loop-step.sh — RALP 단일 스텝 상태 리포터
# 용도: 현재 PROGRESS.json에서 루프 좌표를 추출하여 저수준 모델에 주입할 컨텍스트를 출력한다
# 사용법: bash loop-step.sh [PROGRESS.json 경로] [--format json|text]

set -euo pipefail

PROGRESS_FILE="${1:-./PROGRESS.json}"
FORMAT="${2:---format}"
FORMAT_VALUE="${3:-text}"

# --format 플래그 파싱
if [[ "$FORMAT" == "--format" ]]; then
  FORMAT="$FORMAT_VALUE"
else
  FORMAT="text"
fi

# ────────────────────────────────────────
# 0. 의존성 + 파일 존재 확인
# ────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq가 설치되어 있지 않습니다. brew install jq" >&2
  exit 1
fi

if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "ERROR: PROGRESS.json not found at '$PROGRESS_FILE'" >&2
  echo "HINT: Run harnish Mode A (시딩) first to seed tasks." >&2
  exit 1
fi

if ! jq empty "$PROGRESS_FILE" 2>/dev/null; then
  echo "ERROR: 유효한 JSON이 아닙니다: $PROGRESS_FILE" >&2
  exit 1
fi

# ────────────────────────────────────────
# 1. 좌표 추출
# ────────────────────────────────────────
DOING_NULL=$(jq -r 'if .doing.task == null then "true" else "false" end' "$PROGRESS_FILE")
CURRENT_TASK=$(jq -r '.doing.task.id // ""' "$PROGRESS_FILE")
CURRENT_TITLE=$(jq -r '.doing.task.title // ""' "$PROGRESS_FILE")
NEXT_ACTION=$(jq -r '.doing.task.next_action // ""' "$PROGRESS_FILE")
PRD_PATH=$(jq -r '.metadata.prd // ""' "$PROGRESS_FILE")
CURRENT_PHASE=$(jq -r '.metadata.status.phase // ""' "$PROGRESS_FILE")

# ────────────────────────────────────────
# 2. Todo / Done 카운트
# ────────────────────────────────────────
TODO_COUNT=$(jq '[.todo.phases[].tasks[]] | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")
DONE_COUNT=$(jq '[.done.phases[] | select(.compressed != true) | .tasks[]] | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")

# ────────────────────────────────────────
# 3. 상태 판단
# ────────────────────────────────────────
if [[ "$DOING_NULL" == "true" ]]; then
  STATUS="NO_DOING"
else
  STATUS="ACTIVE"
fi

if [[ "$TODO_COUNT" -eq 0 ]] && [[ "$STATUS" == "NO_DOING" ]]; then
  STATUS="ALL_DONE"
fi

# ────────────────────────────────────────
# 4. Phase 마일스톤 감지
# ────────────────────────────────────────
PHASE_TODO=0
MILESTONE_REACHED="false"
MILESTONE_PHASE=""

if [[ -n "$CURRENT_PHASE" ]] && [[ "$CURRENT_PHASE" != "null" ]]; then
  PHASE_TODO=$(jq --argjson p "$CURRENT_PHASE" \
    '[.todo.phases[] | select(.phase == $p) | .tasks[]] | length' \
    "$PROGRESS_FILE" 2>/dev/null || echo "0")
fi

# NO_DOING + phase의 Todo가 0 = 마일스톤
LAST_DONE_PHASE=$(jq -r '[.done.phases[] | select(.compressed != true)] | last | .phase // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
if [[ "$STATUS" == "NO_DOING" ]] && [[ -n "$LAST_DONE_PHASE" ]]; then
  PHASE_REMAINING=$(jq --argjson p "$LAST_DONE_PHASE" \
    '[.todo.phases[] | select(.phase == $p) | .tasks[]] | length' \
    "$PROGRESS_FILE" 2>/dev/null || echo "0")
  if [[ "$PHASE_REMAINING" -eq 0 ]]; then
    MILESTONE_REACHED="true"
    MILESTONE_PHASE="$LAST_DONE_PHASE"
  fi
fi

# ────────────────────────────────────────
# 5. 출력
# ────────────────────────────────────────
if [[ "$FORMAT" == "json" ]]; then
  jq -n \
    --arg status "$STATUS" \
    --arg task "$CURRENT_TASK" \
    --arg title "$CURRENT_TITLE" \
    --arg phase "$CURRENT_PHASE" \
    --arg next "$NEXT_ACTION" \
    --arg prd "$PRD_PATH" \
    --argjson todo "$TODO_COUNT" \
    --argjson phase_todo "$PHASE_TODO" \
    --arg milestone "$MILESTONE_REACHED" \
    --arg milestone_phase "$MILESTONE_PHASE" \
    --argjson done "$DONE_COUNT" \
    '{
      status: $status,
      current_task: $task,
      current_title: $title,
      current_phase: $phase,
      next_action: $next,
      prd_path: $prd,
      todo_remaining: $todo,
      phase_todo_remaining: $phase_todo,
      phase_milestone: ($milestone == "true"),
      milestone_phase: $milestone_phase,
      done_count: $done
    }'
else
  echo "════════════════════════════════════"
  echo " RALP 루프 현재 좌표"
  echo "════════════════════════════════════"
  echo " STATUS      : $STATUS"
  echo " Phase       : ${CURRENT_PHASE:-미설정}"
  echo " Task ID     : ${CURRENT_TASK:-없음}"
  echo " Title       : ${CURRENT_TITLE:-없음}"
  echo " 다음 액션   : ${NEXT_ACTION:-미설정}"
  echo " PRD         : ${PRD_PATH:-미설정}"
  echo " Phase Todo  : ${PHASE_TODO}개 남음"
  echo " 전체 Todo   : ${TODO_COUNT}개"
  echo " 완료 Done   : ${DONE_COUNT}개"
  if [[ "$MILESTONE_REACHED" == "true" ]]; then
    echo " 마일스톤    : Phase $MILESTONE_PHASE 완료!"
  fi
  echo "════════════════════════════════════"
  echo ""

  case "$STATUS" in
    ACTIVE)
      echo "→ '${NEXT_ACTION:-다음 액션 미설정}'부터 실행을 재개합니다."
      ;;
    NO_DOING)
      if [[ "$MILESTONE_REACHED" == "true" ]]; then
        echo "→ Phase $MILESTONE_PHASE 마일스톤 도달. 사용자 승인 대기."
      else
        echo "→ Doing이 비어있습니다. Todo에서 다음 태스크를 가져옵니다."
      fi
      ;;
    ALL_DONE)
      echo "→ 모든 태스크 완료. 최종 보고를 생성합니다."
      ;;
  esac
fi
