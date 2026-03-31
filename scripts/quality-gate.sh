#!/usr/bin/env bash
# quality-gate.sh — RALP 품질 게이트
#
# Stop/SessionEnd 이벤트에서 1회 실행.
# 이번 세션(오늘)에 기록된 자산들의 완성도를 스캔하고,
# 부족한 항목만 보완 리포트로 출력한다.
#
# 설계 원칙:
#   - 무한 루프 아님 → 1회 스캔, 1회 리포트
#   - hook timeout(15s) 안에 끝나도록 경량 설계
#   - 에이전트에게 "정말 완료됐나?" 질문을 전달하는 게 핵심
#
# v0 설계 메모:
#   - 섹션 검증을 sections.json에서 읽어 하드코딩 제거
#   - "프로젝트 특정 경로" 감지를 절대경로/홈디렉토리 기반으로 변경
#   - 환경변수 해석 안정화
#
# 사용법:
#   quality-gate.sh [--base-dir PATH] [--date YYYY-MM-DD] [--format json|text]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
SKILL_DIR="$(cd "$SCRIPT_DIR/../skills/harnish" && pwd)"
SECTIONS_FILE="$SKILL_DIR/references/sections.json"

# --- 환경변수 ---
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
TARGET_DATE=$(date +"%Y-%m-%d")
FORMAT="json"

while [[ $# -gt 0 ]]; do
    case $1 in
        --base-dir) ASSET_BASE="$2"; shift 2;;
        --date)     TARGET_DATE="$2"; shift 2;;
        --format)   FORMAT="$2"; shift 2;;
        *) shift;;
    esac
done

# ─── 섹션 설정 로드 (sections.json) ───
# 유형별 required_sections와 required_patterns를 반환
get_required_sections() {
    local type="$1"
    if [[ -f "$SECTIONS_FILE" ]]; then
        jq -r --arg t "$type" '.[$t].required_sections // [] | .[]' "$SECTIONS_FILE" 2>/dev/null || echo ""
    else
        # 폴백: sections.json이 없으면 빈 값 (검증 스킵)
        echo ""
    fi
}

get_required_patterns() {
    local type="$1"
    if [[ -f "$SECTIONS_FILE" ]]; then
        jq -r --arg t "$type" '.[$t].required_patterns // [] | .[]' "$SECTIONS_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# ─── 오늘 기록된 자산 수집 ───
ISSUES="[]"
SCANNED=0
GOOD=0
FAIR=0
POOR=0

check_asset() {
    local file="$1"
    local filename=$(basename "$file" .md)
    local fm
    fm=$(parse_frontmatter "$file")
    local type
    type=$(get_field "$fm" "type")
    [[ -z "$type" ]] && type="unknown"
    local tags_val
    tags_val=$(get_tags "$fm")
    local context_val
    context_val=$(get_field "$fm" "context")
    local problems="[]"

    SCANNED=$((SCANNED + 1))

    # 1) 태그 검증
    if [[ -z "$tags_val" ]]; then
        problems=$(echo "$problems" | jq '. + ["tags 비어있음"]')
    else
        # 따옴표를 제거하고 카운트
        local tag_count=$(echo "$tags_val" | tr ',' '\n' | sed 's/"//g' | grep -v '^\s*$' | wc -l | xargs)
        if [[ "$tag_count" -lt 2 ]]; then
            problems=$(echo "$problems" | jq '. + ["태그 부족 (최소 2개 권장, 현재 '"$tag_count"'개)"]')
        fi
    fi

    # 2) context 검증
    if [[ -z "$context_val" ]]; then
        problems=$(echo "$problems" | jq '. + ["context 비어있음"]')
    fi

    # 3) 본문 품질 검증
    local body
    body=$(parse_body "$file")
    local body_text_lines
    body_text_lines=$(echo "$body" | { grep -v "^#" || true; } | { grep -v "^$" || true; } | { grep -v '```' || true; } | wc -l | xargs)

    if [[ "$body_text_lines" -eq 0 ]]; then
        problems=$(echo "$problems" | jq '. + ["본문 내용 없음 (빈 템플릿)"]')
    elif [[ "$body_text_lines" -lt 3 ]]; then
        problems=$(echo "$problems" | jq '. + ["본문이 매우 짧음 ('"$body_text_lines"'줄) — 충분한 맥락이 있나요?"]')
    fi

    # 4) 유형별 필수 섹션 — sections.json 기반
    local required_sections
    required_sections=$(get_required_sections "$type")
    if [[ -n "$required_sections" ]]; then
        while IFS= read -r sec; do
            [[ -z "$sec" ]] && continue
            if echo "$body" | grep -q "## ${sec}"; then
                # 섹션은 있지만 내용이 비어있는지
                local sec_content
                sec_content=$(echo "$body" | sed -n "/## ${sec}/,/## /p" | grep -v "^## " | grep -v "^$" || true)
                if [[ -z "$sec_content" ]]; then
                    problems=$(echo "$problems" | jq --arg s "$sec" '. + [$s + " 섹션이 비어있음"]')
                fi
            else
                problems=$(echo "$problems" | jq --arg s "$sec" '. + [$s + " 섹션 누락"]')
            fi
        done <<< "$required_sections"
    fi

    # 필수 패턴 검증 (snippet의 코드 블록 등)
    local required_patterns
    required_patterns=$(get_required_patterns "$type")
    if [[ -n "$required_patterns" ]]; then
        while IFS= read -r pat; do
            [[ -z "$pat" ]] && continue
            if ! echo "$body" | grep -qF "$pat"; then
                problems=$(echo "$problems" | jq --arg p "$pat" '. + ["필수 패턴 누락: " + $p]')
            fi
        done <<< "$required_patterns"
    fi

    # 5) 일반화 수준 체크 — 절대경로와 사용자별 경로를 감지
    #    기존: src/, app/ 등 범용 디렉토리를 잡았으나, 이는 거짓양성이 많음
    #    개선: 실제로 범용화를 해치는 것은 절대경로, 홈디렉토리, localhost 등
    local specific_refs
    specific_refs=$(echo "$body" | { grep -oE '(/Users/[^ ]+|/home/[^ ]+|/var/[^ ]+|/tmp/[^ ]+|localhost:[0-9]+|127\.0\.0\.[0-9]+:[0-9]+|C:\\[^ ]+)' || true; } | wc -l | xargs)
    if [[ "$specific_refs" -gt 2 ]]; then
        problems=$(echo "$problems" | jq '. + ["머신 특정 경로/참조가 많음 ('"$specific_refs"'건) — 범용화 필요"]')
    fi

    # 판정
    local problem_count
    problem_count=$(echo "$problems" | jq 'length')
    local quality="good"
    if [[ "$problem_count" -ge 3 ]]; then
        quality="poor"
        POOR=$((POOR + 1))
    elif [[ "$problem_count" -ge 1 ]]; then
        quality="fair"
        FAIR=$((FAIR + 1))
    else
        GOOD=$((GOOD + 1))
    fi

    if [[ "$problem_count" -gt 0 ]]; then
        ISSUES=$(echo "$ISSUES" | jq --arg f "$filename" --arg t "$type" --arg q "$quality" --argjson p "$problems" \
            '. + [{file: $f, type: $t, quality: $q, problems: $p}]')
    fi
}

# 오늘 날짜 파일만 스캔
for folder in patterns failures guardrails snippets decisions; do
    dir="$ASSET_BASE/$folder"
    [[ -d "$dir" ]] || continue
    for f in "$dir/${TARGET_DATE}"*.md; do
        [[ -f "$f" ]] || continue
        check_asset "$f"
    done
done

ISSUE_COUNT=$(echo "$ISSUES" | jq 'length')

# ─── 결과 출력 ───
if [[ "$FORMAT" == "json" ]]; then
    jq -n \
        --argjson scanned "$SCANNED" \
        --argjson good "$GOOD" \
        --argjson fair "$FAIR" \
        --argjson poor "$POOR" \
        --argjson issues "$ISSUES" \
        '{
            ralp_gate: "complete",
            summary: {scanned: $scanned, good: $good, fair: $fair, poor: $poor},
            verdict: (if $poor > 0 then "보완 필요 — poor 자산이 있습니다"
                      elif $fair > 0 then "개선 권장 — 일부 자산의 완성도를 높일 수 있습니다"
                      else "통과 — 모든 자산이 양호합니다" end),
            question: (if ($poor + $fair) > 0 then "이 세션의 자산 기록이 정말 완료되었나요? 위 항목들을 보완하시겠습니까?"
                       else null end),
            issues: $issues
        }'
else
    echo "═══ RALP 품질 게이트 ═══"
    echo "스캔: ${SCANNED}건 | 양호: ${GOOD} | 보통: ${FAIR} | 부족: ${POOR}"
    echo ""
    if [[ "$ISSUE_COUNT" -gt 0 ]]; then
        echo "⚠ 보완이 필요한 자산:"
        echo "$ISSUES" | jq -r '.[] | "  [\(.quality)] \(.file) (\(.type))\n    → " + (.problems | join("\n    → "))'
        echo ""
        echo "정말 이대로 세션을 끝내도 괜찮을까요?"
    else
        echo "✓ 모든 자산이 양호합니다."
    fi
fi
