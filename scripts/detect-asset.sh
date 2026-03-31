#!/usr/bin/env bash
# detect-asset.sh — Claude Code hook에서 호출되는 자산 감지 스크립트
#
# 노이즈를 줄이기 위해 다음을 무시한다:
#   - 단순 경로 오류 (No such file or directory)
#   - 권한 문제 (Permission denied)
#   - 일시적 네트워크 오류
#   - lint/format 경고 (단, deprecation은 통과시킴)
#   - 이미 완료된 상태 (already exists, up to date, nothing to commit)
#
# 의미 있는 실패만 pending에 축적하고,
# 같은 도구에서 2회 이상 실패 후 성공 시에만 회복 패턴 신호를 보낸다.
#
# v0 설계 메모:
#   - 세션 기반 추적 (날짜 기반 → session_id 기반, 자정 넘김 문제 해결)
#   - 노이즈 필터 강화 (permission denied 앵커 수정, 신규 패턴 추가)
#   - PostToolUse에서 pending 파일 미존재 시 조기 종료 (불필요 I/O 제거)
#   - 환경변수 해석 안정화

set -euo pipefail

INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date +"%Y-%m-%d")

# --- 환경변수: SCRIPT_DIR 기반 상대경로 우선 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_default_base() {
    if [[ -n "${ASSET_BASE_DIR:-}" ]]; then
        echo "$ASSET_BASE_DIR"
    elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        echo "${CLAUDE_PROJECT_DIR}/_base/assets"
    else
        local harnish_root
        harnish_root="$(cd "$SCRIPT_DIR/.." && pwd)"
        local parent
        parent="$(cd "$harnish_root/.." && pwd)"
        echo "$parent/_base/assets"
    fi
}
ASSET_BASE="$(_default_base)"
PENDING_DIR="${ASSET_BASE}/.meta/pending"

# --- 세션별 실패 로그 파일명 ---
# 날짜가 아닌 session_id 기반으로 추적하여 자정 넘김 문제를 방지한다.
# session_id가 너무 길 수 있으므로 해시로 축약
SESSION_HASH=$(echo -n "$SESSION_ID" | md5sum | cut -c1-8)
FAILURE_LOG="${PENDING_DIR}/failures-s${SESSION_HASH}.jsonl"

# 로그
log() {
    local LOG_FILE="${ASSET_BASE}/.meta/hook.log"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    echo "[${TIMESTAMP}] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# ─── 노이즈 필터: 무시할 에러 패턴 ───
is_noise() {
    local msg="$1"

    # 빈 에러
    [[ -z "$msg" || "$msg" == "null" ]] && return 0

    # 단순 경로/파일 오류
    echo "$msg" | grep -qiE "no such file|not found|command not found" && return 0

    # 권한 문제 (앵커 없이 — 실제 에러 메시지에 경로가 포함됨)
    echo "$msg" | grep -qiE "permission denied" && return 0

    # 네트워크 일시 오류
    echo "$msg" | grep -qiE "connection (refused|reset|timed out)|ECONNREFUSED|ETIMEDOUT|ENOTFOUND|EHOSTUNREACH" && return 0

    # 이미 완료된 상태 (무해한 "실패")
    echo "$msg" | grep -qiE "already exists|already up.to.date|nothing to commit|no changes" && return 0

    # lint/format 경고 — 단, deprecation은 통과시킴 (의미 있는 경고)
    if echo "$msg" | grep -qiE "warning:|note:|hint:"; then
        # deprecation 관련이면 노이즈가 아님
        echo "$msg" | grep -qiE "deprecat" && return 1
        return 0
    fi

    return 1
}

# ─── PostToolUseFailure: 의미 있는 실패만 축적 ───
if [ "$HOOK_EVENT" = "PostToolUseFailure" ]; then
    ERROR_MSG=$(echo "$INPUT" | jq -r '.tool_output // .tool_error // ""' | head -c 500)

    # 노이즈 필터
    if is_noise "$ERROR_MSG"; then
        log "NOISE (ignored): ${TOOL_NAME} — ${ERROR_MSG:0:100}"
        exit 0
    fi

    log "FAILURE: ${TOOL_NAME} — ${ERROR_MSG:0:200}"

    mkdir -p "$PENDING_DIR"
    echo "$INPUT" | jq -c "{
        type: \"failure\",
        timestamp: \"${TIMESTAMP}\",
        tool: \"${TOOL_NAME}\",
        error: (.tool_output // .tool_error // \"\") | .[0:500],
        session_id: \"${SESSION_ID}\"
    }" >> "$FAILURE_LOG"

    # 같은 도구에서 누적 실패 횟수
    FAIL_COUNT=$(grep -c "\"tool\":\"${TOOL_NAME}\"" "$FAILURE_LOG" 2>/dev/null || echo "0")

    # 2회 이상 실패해야 신호 (1회는 노이즈일 수 있음)
    if [ "$FAIL_COUNT" -ge 2 ]; then
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUseFailure\",\"additionalContext\":\"[asset-recorder] ${TOOL_NAME}이 ${FAIL_COUNT}회 실패했습니다. 해결되면 실패 원인·해결법·일반화된 패턴을 _base/assets/failures/에 기록하세요.\"}}"
    fi

    exit 0
fi

# ─── PostToolUse: 회복 패턴 감지 (2회+ 실패 후 성공) ───
if [ "$HOOK_EVENT" = "PostToolUse" ]; then
    # 조기 종료: pending 파일이 없으면 체크할 이유가 없음
    if [ ! -f "$FAILURE_LOG" ]; then
        exit 0
    fi

    # 해당 도구의 이전 실패가 있는지만 빠르게 확인
    PREV_FAILURES=$(grep -c "\"tool\":\"${TOOL_NAME}\"" "$FAILURE_LOG" 2>/dev/null || echo "0")

    if [ "$PREV_FAILURES" -ge 2 ]; then
        log "RECOVERY: ${TOOL_NAME} succeeded after ${PREV_FAILURES} failure(s)"

        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"[asset-recorder] ${TOOL_NAME}이 ${PREV_FAILURES}회 실패 후 성공했습니다. 이 해결 과정을 자산으로 기록할 가치가 있다면 record-asset.sh를 사용하세요. 기록 시 포함할 것: 표면 증상, 실제 원인, 해결 과정, 일반화 패턴.\"}}"

        # 감지한 실패 로그를 consumed로 이동 (재감지 방지)
        CONSUMED_DIR="${PENDING_DIR}/consumed"
        mkdir -p "$CONSUMED_DIR"
        grep "\"tool\":\"${TOOL_NAME}\"" "$FAILURE_LOG" >> "${CONSUMED_DIR}/failures-s${SESSION_HASH}.jsonl" 2>/dev/null || true
        # 원본에서 해당 도구 실패 제거
        grep -v "\"tool\":\"${TOOL_NAME}\"" "$FAILURE_LOG" > "${FAILURE_LOG}.tmp" 2>/dev/null || true
        mv "${FAILURE_LOG}.tmp" "$FAILURE_LOG" 2>/dev/null || true

        # 빈 파일이면 삭제하여 다음 PostToolUse에서 조기 종료
        if [ ! -s "$FAILURE_LOG" ]; then
            rm -f "$FAILURE_LOG" 2>/dev/null || true
        fi
    fi

    exit 0
fi

# ─── Stop/SessionEnd: 임계치 확인 + RALP 품질 게이트 ───
if [ "$HOOK_EVENT" = "Stop" ] || [ "$HOOK_EVENT" = "SessionEnd" ]; then
    MESSAGES=()

    # 1) 임계치 확인 (compression + skillification)
    INDEX_FILE="${ASSET_BASE}/.meta/index.json"
    if [ -f "$INDEX_FILE" ]; then
        THRESHOLD=$(jq -r '.thresholds.compression_trigger // 5' "$INDEX_FILE")
        ALERT_MSG=$(jq -r --argjson thr "$THRESHOLD" \
            '[.tag_index | to_entries[] | select(.value >= $thr) | "\(.key)(\(.value)건)"] | join(", ")' \
            "$INDEX_FILE" 2>/dev/null || echo "")

        if [ -n "$ALERT_MSG" ]; then
            log "THRESHOLD: ${ALERT_MSG}"
            MESSAGES+=("임계치 도달 태그: ${ALERT_MSG}. 압축/스킬화 여부를 확인하세요.")
        fi

        # stability 기반 스킬화 후보 확인
        SKILL_THR=$(jq -r '.thresholds.skillification_stability // 3' "$INDEX_FILE")
        SKILL_CANDIDATES=""
        for folder in patterns snippets; do
            sdir="$ASSET_BASE/$folder"
            [ -d "$sdir" ] || continue
            for sf in "$sdir"/*.md; do
                [ -f "$sf" ] || continue
                stab=$(grep -E 'stability:' "$sf" 2>/dev/null | head -1 | sed 's/.*stability:[[:space:]]*//' || echo "0")
                [[ -z "$stab" ]] && stab="0"
                if [ "$stab" -ge "$SKILL_THR" ]; then
                    sfname=$(basename "$sf" .md)
                    SKILL_CANDIDATES="${SKILL_CANDIDATES}${sfname}(stability=${stab}), "
                fi
            done
        done
        if [ -n "$SKILL_CANDIDATES" ]; then
            log "SKILLIFY: ${SKILL_CANDIDATES}"
            MESSAGES+=("스킬화 후보: ${SKILL_CANDIDATES%%, }.")
        fi
    fi

    # 2) RALP 품질 게이트 (오늘 기록된 자산 스캔)
    GATE_RESULT=$(bash "${SCRIPT_DIR}/quality-gate.sh" --base-dir "$ASSET_BASE" --format json 2>/dev/null || echo "{}")
    GATE_VERDICT=$(echo "$GATE_RESULT" | jq -r '.verdict // empty' 2>/dev/null || echo "")
    GATE_QUESTION=$(echo "$GATE_RESULT" | jq -r '.question // empty' 2>/dev/null || echo "")
    GATE_POOR=$(echo "$GATE_RESULT" | jq -r '.summary.poor // 0' 2>/dev/null || echo "0")
    GATE_FAIR=$(echo "$GATE_RESULT" | jq -r '.summary.fair // 0' 2>/dev/null || echo "0")
    GATE_SCANNED=$(echo "$GATE_RESULT" | jq -r '.summary.scanned // 0' 2>/dev/null || echo "0")

    if [ "$GATE_SCANNED" -gt 0 ]; then
        if [ "$GATE_POOR" -gt 0 ] || [ "$GATE_FAIR" -gt 0 ]; then
            ISSUE_SUMMARY=$(echo "$GATE_RESULT" | jq -r '[.issues[] | "[\(.quality)] \(.file): " + (.problems | join(", "))] | join("; ")' 2>/dev/null || echo "")
            log "RALP: ${GATE_VERDICT}"
            MESSAGES+=("[RALP] ${GATE_VERDICT}. ${ISSUE_SUMMARY}. ${GATE_QUESTION}")
        else
            log "RALP: all assets good (${GATE_SCANNED} scanned)"
        fi
    fi

    # 3) pending 실패 중 미해결 건 — 현재 세션 + 이전 세션 잔여분 모두 확인
    TOTAL_UNRESOLVED=0
    if [ -d "$PENDING_DIR" ]; then
        for pf in "$PENDING_DIR"/failures-s*.jsonl; do
            [ -f "$pf" ] || continue
            local_count=$(wc -l < "$pf" | xargs)
            TOTAL_UNRESOLVED=$((TOTAL_UNRESOLVED + local_count))
        done
    fi
    if [ "$TOTAL_UNRESOLVED" -gt 0 ]; then
        log "UNRESOLVED: ${TOTAL_UNRESOLVED} failures at session end"
        MESSAGES+=("미해결 실패 ${TOTAL_UNRESOLVED}건이 있습니다. 기록할 가치가 있는지 확인하세요.")
    fi

    # 메시지 결합 출력
    if [ ${#MESSAGES[@]} -gt 0 ]; then
        COMBINED=$(printf "%s " "${MESSAGES[@]}")
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"${HOOK_EVENT}\",\"additionalContext\":\"[asset-recorder] ${COMBINED}\"}}"
    fi

    exit 0
fi

exit 0
