#!/usr/bin/env bash
# progress-report.sh — PROGRESS.json → 사람용 마크다운 렌더링
#
# 사용법: bash progress-report.sh [PROGRESS.json 경로]
# 출력: stdout (markdown)

set -euo pipefail

PROGRESS_FILE="${1:-./PROGRESS.json}"

if ! command -v jq &>/dev/null; then
    echo "오류: jq가 설치되어 있지 않습니다. brew install jq" >&2
    exit 1
fi

if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "오류: PROGRESS.json 없음: $PROGRESS_FILE" >&2
    exit 1
fi

# ── 메타데이터 ──
echo "# PROGRESS — 자동 갱신 진행 상태"
echo ""
echo "## 메타데이터"
jq -r '"- **PRD**: \(.metadata.prd)
- **시작**: \(.metadata.started_at)
- **마지막 세션**: \(.metadata.last_session)
- **현재 상태**: \(.metadata.status.emoji) Phase \(.metadata.status.phase) / Task \(.metadata.status.task) \(.metadata.status.label)"' "$PROGRESS_FILE"
echo ""
echo "---"
echo ""

# ── Done ──
echo "## ✅ 완료 (Done)"
echo ""

PHASE_COUNT=$(jq '.done.phases | length' "$PROGRESS_FILE")
if [[ "$PHASE_COUNT" -eq 0 ]]; then
    echo "(없음)"
else
    jq -r '.done.phases[] |
      if .compressed then
        "### Phase \(.phase): \(.title) ✅ [압축됨]\n- \(.compressed_summary)\n- archive: \(.archive_ref)\n"
      else
        "### Phase \(.phase): \(.title)\n" +
        ([.tasks[] |
          "- [x] Task \(.id): \(.title)\n  - **결과**: \(.result // "미기록")\n  - **변경 파일**: \(.files_changed | join(", "))\n  - **검증**: \(.verification // "미기록")\n  - **소요**: \(.duration // "미기록")"
        ] | join("\n")) + "\n"
      end' "$PROGRESS_FILE"
fi
echo ""
echo "---"
echo ""

# ── Doing ──
echo "## 🔨 진행 중 (Doing)"
echo ""

DOING_NULL=$(jq 'if .doing.task == null then "true" else "false" end' "$PROGRESS_FILE")
if [[ "$DOING_NULL" == '"true"' ]]; then
    echo "(없음)"
else
    jq -r '.doing.task |
      "### Task \(.id): \(.title)\n
- **시작**: \(.started_at)
- **현재**: \(.current // "미설정")
- **마지막 액션**: \(.last_action // "미설정")
- **다음 액션**: \(.next_action // "미설정")
- **블로커**: \(.blocker // "없음")
- **시도 횟수**: \(.retry_count // 0)

#### 태스크 컨텍스트
- **가이드**: \(.context.guide // "미설정")
- **scope**: \(.context.scope // "미설정")
- **참조 PRD**: \(.context.prd_reference // "미설정")"' "$PROGRESS_FILE"
fi
echo ""
echo "---"
echo ""

# ── Todo ──
echo "## 📋 예정 (Todo)"
echo ""

TODO_PHASES=$(jq '.todo.phases | length' "$PROGRESS_FILE")
if [[ "$TODO_PHASES" -eq 0 ]]; then
    echo "(없음)"
else
    jq -r '.todo.phases[] |
      "### Phase \(.phase): \(.title)\n" +
      ([.tasks[] |
        "- [ ] Task \(.id): \(.title)" +
        (if (.depends_on | length) > 0 then " (← Task \(.depends_on | join(", ")) 필요)" else "" end)
      ] | join("\n")) + "\n"' "$PROGRESS_FILE"
fi
echo ""
echo "---"
echo ""

# ── Issues ──
echo "## ⚠️ 이슈 · 결정 로그"
echo ""
ISSUES=$(jq '.issues | length' "$PROGRESS_FILE")
if [[ "$ISSUES" -eq 0 ]]; then
    echo "| 시점 | 태스크 | 내용 | 결정/해결 |"
    echo "|------|--------|------|----------|"
    echo "| (없음) | | | |"
else
    echo "| 시점 | 태스크 | 내용 | 결정/해결 |"
    echo "|------|--------|------|----------|"
    jq -r '.issues[] | "| \(.timestamp) | \(.task) | \(.description) | \(.resolution // "미결") |"' "$PROGRESS_FILE"
fi
echo ""
echo "---"
echo ""

# ── Violations ──
echo "## 🔴 금지사항 위반 기록"
echo ""
echo "| 시점 | 태스크 | 위반 내용 | 사용자 판단 |"
echo "|------|--------|----------|-----------|"
VIOLATIONS=$(jq '.violations | length' "$PROGRESS_FILE")
if [[ "$VIOLATIONS" -eq 0 ]]; then
    echo "| (없음) | | | |"
else
    jq -r '.violations[] | "| \(.timestamp) | \(.task) | \(.violation) | \(.user_decision // "미결") |"' "$PROGRESS_FILE"
fi
echo ""
echo "---"
echo ""

# ── Stats ──
echo "## 📊 요약 통계"
echo ""
jq -r '.stats |
"- 전체 페이즈: \(.total_phases)개
- 완료 페이즈: \(.completed_phases)개
- 전체 태스크: \(.total_tasks)개
- 완료 태스크: \(.completed_tasks)개
- 이슈 발생: \(.issues_count)건
- 금지사항 위반: \(.violations_count)건"' "$PROGRESS_FILE"
