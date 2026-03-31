#!/usr/bin/env bash
# validate-progress.sh — PROGRESS.json 구조 검증 스크립트
#
# 역할: PROGRESS.json이 harnish가 파싱할 수 있는 올바른 구조인지 검증한다.
#       세션 시작 시, 마일스톤 도달 시 자동 실행.
#
# 사용법:
#   bash validate-progress.sh [PROGRESS.json 경로]
#   bash validate-progress.sh                     # 현재 디렉토리의 PROGRESS.json
#
# 종료 코드:
#   0 — 구조 정상
#   1 — 구조 오류 발견 (상세 내용은 stderr)

set -euo pipefail

PROGRESS_FILE="${1:-PROGRESS.json}"

# ═══════════════════════════════════════
# 의존성 체크
# ═══════════════════════════════════════
if ! command -v jq &>/dev/null; then
    echo "오류: jq가 설치되어 있지 않습니다. brew install jq" >&2
    exit 1
fi

# ═══════════════════════════════════════
# 파일 존재 확인
# ═══════════════════════════════════════
if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "오류: PROGRESS.json 없음: $PROGRESS_FILE" >&2
    exit 1
fi

# ═══════════════════════════════════════
# JSON 유효성 확인
# ═══════════════════════════════════════
if ! jq empty "$PROGRESS_FILE" 2>/dev/null; then
    echo "오류: 유효한 JSON이 아닙니다: $PROGRESS_FILE" >&2
    exit 1
fi

ERRORS=()
WARNINGS=()

# ═══════════════════════════════════════
# 필수 최상위 키 검증
# ═══════════════════════════════════════
for key in metadata done doing todo; do
    if ! jq -e ".$key" "$PROGRESS_FILE" >/dev/null 2>&1; then
        ERRORS+=("필수 키 누락: '$key'")
    fi
done

# ═══════════════════════════════════════
# 메타데이터 필드 검증
# ═══════════════════════════════════════
for field in prd started_at last_session status; do
    if ! jq -e ".metadata.$field" "$PROGRESS_FILE" >/dev/null 2>&1; then
        ERRORS+=("메타데이터 필수 필드 누락: '$field'")
    fi
done

# ═══════════════════════════════════════
# 상태 이모지 검증
# ═══════════════════════════════════════
EMOJI=$(jq -r '.metadata.status.emoji // ""' "$PROGRESS_FILE")
if [[ -n "$EMOJI" ]]; then
    case "$EMOJI" in
        "🟢"|"🟡"|"🔴"|"✅") ;;
        *) WARNINGS+=("현재 상태에 유효한 상태 이모지(🟢🟡🔴✅) 없음: '$EMOJI'");;
    esac
fi

# ═══════════════════════════════════════
# Doing 태스크 필수 필드 검증
# ═══════════════════════════════════════
DOING_TASK=$(jq -r '.doing.task // "null"' "$PROGRESS_FILE")
if [[ "$DOING_TASK" != "null" ]]; then
    for field in id title started_at current next_action; do
        val=$(jq -r ".doing.task.$field // \"\"" "$PROGRESS_FILE")
        if [[ -z "$val" ]]; then
            WARNINGS+=("진행 중 태스크에 '$field' 필드 누락 — 세션 복원 정확도 저하")
        fi
    done
fi

# ═══════════════════════════════════════
# Done 태스크 구조 검증
# ═══════════════════════════════════════
DONE_TASKS=$(jq '[.done.phases[] | select(.compressed != true) | .tasks[]] | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")
if [[ "$DONE_TASKS" -gt 0 ]]; then
    NO_RESULT=$(jq '[.done.phases[] | select(.compressed != true) | .tasks[] | select(.result == null or .result == "")] | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")
    if [[ "$NO_RESULT" -gt 0 ]]; then
        WARNINGS+=("완료된 태스크 ${NO_RESULT}건에 'result' 필드 없음")
    fi
fi

# ═══════════════════════════════════════
# 선택 키 검증
# ═══════════════════════════════════════
for key in issues violations escalations stats; do
    if ! jq -e ".$key" "$PROGRESS_FILE" >/dev/null 2>&1; then
        WARNINGS+=("선택 키 누락: '$key' — 있으면 추적이 용이")
    fi
done

# ═══════════════════════════════════════
# 결과 출력
# ═══════════════════════════════════════
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "❌ PROGRESS.json 구조 오류 발견:" >&2
    for err in "${ERRORS[@]}"; do
        echo "  • $err" >&2
    done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "⚠️ 경고:" >&2
    for warn in "${WARNINGS[@]}"; do
        echo "  • $warn" >&2
    done
fi

if [[ ${#ERRORS[@]} -eq 0 ]]; then
    echo "✅ PROGRESS.json 구조 정상 (경고 ${#WARNINGS[@]}건)"
    exit 0
else
    echo "❌ 구조 오류 ${#ERRORS[@]}건, 경고 ${#WARNINGS[@]}건" >&2
    exit 1
fi
