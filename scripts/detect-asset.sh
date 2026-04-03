#!/usr/bin/env bash
# detect-asset.sh — Claude Code hook에서 호출. 자산 감지 + pending 관리.
#
# 노이즈 줄이기: 단순 오류, 테스트 실행, 읽기 전용 작업은 무시.
# pending은 /tmp에 저장 (세션 내 임시 데이터, RAG 오염 방지).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE="$(resolve_base_dir)"
RAG_FILE="$BASE/harnish-rag.jsonl"

# hook은 조용히 실패해야 함
trap 'exit 0' ERR

# .harnish/ 없으면 무시
[[ -d "$BASE" ]] || exit 0

# 세션 해시
if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
    SESSION_HASH="$CLAUDE_SESSION_ID"
else
    SESSION_HASH=$(echo "$$" | md5 2>/dev/null | cut -c1-8 || echo "$$" | md5sum 2>/dev/null | cut -c1-8 || echo "unknown")
fi
PENDING_FILE="/tmp/harnish-pending-${SESSION_HASH}.jsonl"

# stdin에서 hook JSON 읽기 (없으면 빈 문자열)
INPUT=""
if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || true)
fi

# JSON이 아니면 무시
if [[ -z "$INPUT" ]] || ! echo "$INPUT" | jq empty 2>/dev/null; then
    # pending 파일이 있으면 보고만
    if [[ -f "$PENDING_FILE" ]] && [[ -s "$PENDING_FILE" ]]; then
        PENDING_COUNT=$(wc -l < "$PENDING_FILE" | xargs)
        echo "harnish: ${PENDING_COUNT}건 pending 자산 감지됨"
    fi
    exit 0
fi

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# ── Stop 이벤트: 임계치 + 품질 게이트 ──
if [[ "$EVENT" == "Stop" ]]; then
    # 임계치 확인
    if [[ -f "$RAG_FILE" ]] && [[ -s "$RAG_FILE" ]]; then
        THRESHOLD_OUT=$(bash "$SCRIPT_DIR/check-thresholds.sh" --base-dir "$BASE" 2>/dev/null || true)
        if [[ -n "$THRESHOLD_OUT" ]]; then
            echo "$THRESHOLD_OUT"
        fi
    fi

    # pending 보고
    if [[ -f "$PENDING_FILE" ]] && [[ -s "$PENDING_FILE" ]]; then
        PENDING_COUNT=$(wc -l < "$PENDING_FILE" | xargs)
        echo "harnish: 세션 종료 — ${PENDING_COUNT}건 pending 자산 미처리"
    fi
    exit 0
fi

# ── PostToolUseFailure: 의미 있는 에러만 pending에 기록 ──
if [[ "$EVENT" == "PostToolUseFailure" ]]; then
    # 노이즈 필터: 단순/일반적 에러는 무시
    NOISE_PATTERNS="No such file|permission denied|command not found|not a directory|Is a directory|syntax error near|unexpected token"
    if echo "$TOOL_OUTPUT" | grep -qiE "$NOISE_PATTERNS" 2>/dev/null; then
        exit 0
    fi

    # 빈 출력 무시
    if [[ -z "$TOOL_OUTPUT" ]]; then
        exit 0
    fi

    # pending 파일 용량 제한 (최대 500줄, 초과 시 최근 250줄만 유지)
    MAX_PENDING=500
    if [[ -f "$PENDING_FILE" ]]; then
        CURRENT_LINES=$(wc -l < "$PENDING_FILE" | xargs)
        if [[ "$CURRENT_LINES" -ge "$MAX_PENDING" ]]; then
            TRIMMED=$(mktemp)
            tail -250 "$PENDING_FILE" > "$TRIMMED"
            mv "$TRIMMED" "$PENDING_FILE"
        fi
    fi

    # tool_output 크기 제한 (최대 2000자)
    if [[ ${#TOOL_OUTPUT} -gt 2000 ]]; then
        TOOL_OUTPUT="${TOOL_OUTPUT:0:2000}...(truncated)"
    fi

    # 의미 있는 에러 → pending 기록
    PENDING_RECORD=$(jq -n -c \
        --arg event "$EVENT" \
        --arg tool "$TOOL_NAME" \
        --arg output "$TOOL_OUTPUT" \
        --arg session "$SESSION_ID" \
        --arg date "$(date +%Y-%m-%dT%H:%M:%S)" \
        '{event:$event, tool:$tool, output:$output, session:$session, date:$date}')

    echo "$PENDING_RECORD" >> "$PENDING_FILE"
    PENDING_COUNT=$(wc -l < "$PENDING_FILE" | xargs)
    echo "harnish: 에러 감지 → pending (${PENDING_COUNT}건)"
    exit 0
fi

# ── PostToolUse: 성공 이벤트는 현재 보고만 ──
if [[ "$EVENT" == "PostToolUse" ]]; then
    if [[ -f "$PENDING_FILE" ]] && [[ -s "$PENDING_FILE" ]]; then
        PENDING_COUNT=$(wc -l < "$PENDING_FILE" | xargs)
        echo "harnish: ${PENDING_COUNT}건 pending 자산 감지됨"
    fi
    exit 0
fi

exit 0
