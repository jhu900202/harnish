#!/usr/bin/env bash
# loop-step.sh — RALP 단일 스텝 상태 리포터
# 용도: 현재 PROGRESS.md에서 루프 좌표를 추출하여 저수준 모델에 주입할 컨텍스트를 출력한다
# 사용법: bash loop-step.sh [PROGRESS.md 경로] [--format json|text]

set -euo pipefail

PROGRESS_FILE="${1:-./PROGRESS.md}"
FORMAT="${2:---format}"
FORMAT_VALUE="${3:-text}"

# --format 플래그 파싱
if [[ "$FORMAT" == "--format" ]]; then
  FORMAT="$FORMAT_VALUE"
else
  FORMAT="text"
fi

# ────────────────────────────────────────
# 0. 파일 존재 확인
# ────────────────────────────────────────
if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "ERROR: PROGRESS.md not found at '$PROGRESS_FILE'" >&2
  echo "HINT: Run harnish Mode A (시딩) first to seed tasks." >&2
  exit 1
fi

# ────────────────────────────────────────
# 1. Doing 섹션 추출
# ────────────────────────────────────────
DOING_SECTION=$(awk '/^## 🔨 진행 중 \(Doing\)/,/^## 📋 예정 \(Todo\)/' "$PROGRESS_FILE" 2>/dev/null || true)

if [[ -z "$DOING_SECTION" ]]; then
  echo "ERROR: Cannot find '## 🔨 진행 중 (Doing)' section in $PROGRESS_FILE" >&2
  exit 2
fi

# ────────────────────────────────────────
# 2. 좌표 추출
# ────────────────────────────────────────
# Task ID에서 trailing colon 제거 (### Task 1-2: 제목 → "1-2")
CURRENT_TASK=$(echo "$DOING_SECTION" | grep -E '^### Task' | head -1 | awk '{print $3}' | sed 's/:$//' || echo "")
CURRENT_TITLE=$(echo "$DOING_SECTION" | grep -E '^### Task' | head -1 | sed 's/^### Task [^ ]* //' | sed 's/ ⟳.*//' || echo "")
NEXT_ACTION=$(echo "$DOING_SECTION" | grep -E '다음 액션:' | head -1 | sed 's/.*다음 액션: //' || echo "")
# PRD 경로는 메타데이터 섹션에서 추출 (Doing 섹션의 "참조: PRD §N"은 경로가 아님)
PRD_PATH=$(awk '/^## 메타데이터/,/^---/' "$PROGRESS_FILE" | grep -E '^- PRD:' | head -1 | sed 's/^- PRD: //' || echo "")
# Phase는 태스크 ID 앞 숫자에서 추출 (예: "1-3" → phase "1")
# POSIX 호환: grep -oP 대신 sed 사용 (macOS BSD grep은 -P 미지원)
CURRENT_PHASE=$(echo "$CURRENT_TASK" | sed -n 's/^\([0-9]*\)-.*/\1/p' || echo "")

# ────────────────────────────────────────
# 3. Todo 확인 (Doing이 비어있을 때)
# ────────────────────────────────────────
TODO_SECTION=$(awk '/^## 📋 예정 \(Todo\)/,/^## ✅ 완료|^---/' "$PROGRESS_FILE" 2>/dev/null || true)
TODO_COUNT=$(echo "$TODO_SECTION" | grep -cE '^\- \[ \]' || true)
DONE_COUNT=$(grep -cE '^\- \[x\]' "$PROGRESS_FILE" 2>/dev/null || true)

# ────────────────────────────────────────
# 4. 상태 판단 + 마일스톤 감지
# ────────────────────────────────────────
if [[ -z "$CURRENT_TASK" ]]; then
  STATUS="NO_DOING"
else
  STATUS="ACTIVE"
fi

if [[ "$TODO_COUNT" -eq 0 ]] && [[ "$STATUS" == "NO_DOING" ]]; then
  STATUS="ALL_DONE"
fi

# ────────────────────────────────────────
# Phase 마일스톤 감지
# ────────────────────────────────────────
# STATUS=NO_DOING일 때: Done 섹션에서 가장 최근 완료 Phase를 찾아
# 해당 Phase의 Todo가 남아있는지 확인한다.
# (CURRENT_PHASE는 CURRENT_TASK에서 추출하므로 NO_DOING 시 항상 empty — Done 섹션 필요)
DONE_SECTION_RAW=$(awk '/^## ✅ 완료 \(Done\)/,/^## 🔨 진행 중/' "$PROGRESS_FILE" 2>/dev/null || true)
# POSIX 호환: grep -P/-oP 대신 grep -E + sed 조합 (macOS BSD grep은 -P 미지원)
LAST_DONE_PHASE=$(echo "$DONE_SECTION_RAW" \
  | grep -E '^### Phase [0-9]+' \
  | grep -v '✅ \[압축됨\]' \
  | sed -n 's/^### Phase \([0-9]*\).*/\1/p' \
  | tail -1 || echo "")

PHASE_TODO_COUNT=0
PHASE_MILESTONE=false
MILESTONE_PHASE=""

if [[ "$STATUS" == "NO_DOING" && -n "$LAST_DONE_PHASE" ]]; then
  PHASE_TODO_COUNT=$(echo "$TODO_SECTION" | grep -cE "^\- \[ \] Task ${LAST_DONE_PHASE}-" || true)
  if [[ "$PHASE_TODO_COUNT" -eq 0 && "$TODO_COUNT" -gt 0 ]]; then
    PHASE_MILESTONE=true
    MILESTONE_PHASE="$LAST_DONE_PHASE"
  fi
elif [[ -n "$CURRENT_PHASE" ]]; then
  # ACTIVE 상태: 현재 Phase의 남은 Todo 미리 계산 (참고용)
  PHASE_TODO_COUNT=$(echo "$TODO_SECTION" | grep -cE "^\- \[ \] Task ${CURRENT_PHASE}-" || true)
fi

# ────────────────────────────────────────
# 5. 출력
# ────────────────────────────────────────
if [[ "$FORMAT" == "json" ]]; then
  cat <<JSON
{
  "status": "$STATUS",
  "current_task": "$CURRENT_TASK",
  "current_title": "$CURRENT_TITLE",
  "current_phase": "$CURRENT_PHASE",
  "next_action": "$NEXT_ACTION",
  "prd_path": "$PRD_PATH",
  "todo_remaining": $TODO_COUNT,
  "phase_todo_remaining": $PHASE_TODO_COUNT,
  "phase_milestone": $PHASE_MILESTONE,
  "milestone_phase": "${MILESTONE_PHASE}",
  "done_count": $DONE_COUNT
}
JSON
else
  echo "════════════════════════════════════"
  echo " RALP 루프 현재 좌표"
  echo "════════════════════════════════════"
  echo " STATUS      : $STATUS"
  echo " Phase       : ${CURRENT_PHASE:-미확인}"
  echo " Task ID     : ${CURRENT_TASK:-없음}"
  echo " Title       : ${CURRENT_TITLE:-없음}"
  echo " 다음 액션   : ${NEXT_ACTION:-미설정}"
  echo " PRD         : ${PRD_PATH:-미설정}"
  echo " Phase Todo  : ${PHASE_TODO_COUNT}개 남음"
  echo " 전체 Todo   : ${TODO_COUNT}개"
  echo " 완료 Done   : ${DONE_COUNT}개"
  echo "════════════════════════════════════"

  if [[ "$PHASE_MILESTONE" == "true" ]]; then
    echo ""
    echo "🏁 Phase ${MILESTONE_PHASE} 마일스톤! 체크포인트 보고 후 압축을 실행하세요:"
    echo "   bash \"\${COMPRESS_SCRIPT}\" ./PROGRESS.md --trigger milestone --phase ${MILESTONE_PHASE}"
  elif [[ "$STATUS" == "NO_DOING" ]]; then
    echo ""
    echo "⚠️  Doing 태스크 없음 — Todo에서 첫 번째 태스크를 Doing으로 이동하세요."
  elif [[ "$STATUS" == "ALL_DONE" ]]; then
    echo ""
    if [[ -n "$LAST_DONE_PHASE" ]]; then
      echo "🏁 마지막 Phase ${LAST_DONE_PHASE} 압축 후 완료 보고를 작성하세요:"
      echo "   bash \"\${COMPRESS_SCRIPT}\" ./PROGRESS.md --trigger milestone --phase ${LAST_DONE_PHASE}"
    else
      echo "🎉 모든 태스크 완료! 완료 보고를 작성하세요."
    fi
  else
    echo ""
    echo "→ '${NEXT_ACTION:-다음 액션 미설정}'부터 실행을 재개합니다."
  fi
fi
