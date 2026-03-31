#!/usr/bin/env bash
# check-thresholds.sh — 자산 인덱스를 읽어 임계치 도달 여부를 확인하고 보고한다.
#
# Layer: L3 (Aggregate)
# 의존: common.sh (L1)
# 규칙: L1 source 가능, L2 호출 가능. 다중 자산 분석.
#
# 설계 원칙:
#   - index.json을 single source of truth로 신뢰 (record-asset.sh가 갱신)
#   - --rebuild 플래그 시에만 전체 파일 스캔 (평소에는 인덱스만 읽기 → 빠름)
#   - hook timeout(10초) 안에 완료 가능하도록 경량 설계
#
# v0 설계 메모:
#   - 기본 동작: index.json만 읽기 (O(1)) → --rebuild 시에만 전체 스캔
#   - 따옴표 포함 YAML 태그 파싱
#   - 환경변수 안정화 + atomic write
#
# 사용법:
#   check-thresholds.sh                          # 텍스트 출력 (인덱스만 읽기)
#   check-thresholds.sh --format json            # JSON 출력
#   check-thresholds.sh --rebuild                # 전체 파일 스캔 후 인덱스 재구축
#   check-thresholds.sh --base-dir /path/to/assets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ASSET_BASE="$(resolve_base_dir)"
FORMAT="text"
REBUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --base-dir) ASSET_BASE="$2"; shift 2;;
        --format)   FORMAT="$2"; shift 2;;
        --rebuild)  REBUILD=true; shift;;
        *) shift;;
    esac
done

INDEX_FILE="$ASSET_BASE/.meta/index.json"

# --- 실제 파일 스캔으로 counts 재구축 (--rebuild 시에만) ---
rebuild_counts() {
    local counts='{}'
    local tag_index='{}'

    for folder in patterns failures guardrails snippets decisions; do
        local dir="$ASSET_BASE/$folder"
        if [[ -d "$dir" ]]; then
            local count=$(find "$dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | xargs)
        else
            local count=0
        fi
        counts=$(echo "$counts" | jq --arg k "$folder" --argjson v "$count" '.[$k] = $v')

        # 각 파일에서 tags 추출 (따옴표 포함 태그도 처리)
        if [[ -d "$dir" ]]; then
            for f in "$dir"/*.md; do
                [[ -f "$f" ]] || continue
                local fm_tmp
                fm_tmp=$(parse_frontmatter "$f")
                local tags_line
                tags_line=$(get_tags "$fm_tmp")
                if [[ -n "$tags_line" ]]; then
                    IFS=',' read -ra tags <<< "$tags_line"
                    for tag in "${tags[@]}"; do
                        tag=$(echo "$tag" | xargs | tr -d '"' | tr -d "'")
                        [[ -z "$tag" ]] && continue
                        tag_index=$(echo "$tag_index" | jq --arg t "$tag" '.[$t] = ((.[$t] // 0) + 1)')
                    done
                fi
            done
        fi
    done

    echo "{\"counts\": $counts, \"tag_index\": $tag_index}"
}

# --- 인덱스가 없으면 안내 ---
if [[ ! -f "$INDEX_FILE" ]]; then
    if [[ "$FORMAT" == "json" ]]; then
        echo '{"status":"no_index","message":"인덱스 파일이 없습니다. init-assets.sh를 실행하세요."}'
    else
        echo "인덱스 파일이 없습니다. 자산이 아직 기록되지 않았습니다."
    fi
    exit 0
fi

# --- rebuild 모드: 전체 스캔 후 인덱스 갱신 ---
if $REBUILD; then
    SCAN=$(rebuild_counts)
    COUNTS=$(echo "$SCAN" | jq '.counts')
    TAG_INDEX=$(echo "$SCAN" | jq '.tag_index')

    # atomic write
    jq --argjson c "$COUNTS" --argjson t "$TAG_INDEX" \
        '.counts = $c | .tag_index = $t' "$INDEX_FILE" > "${INDEX_FILE}.tmp" && \
        mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
else
    # 기본 모드: index.json만 읽기 (빠름)
    COUNTS=$(jq '.counts' "$INDEX_FILE")
    TAG_INDEX=$(jq '.tag_index' "$INDEX_FILE")
fi

# --- 임계치 확인 ---
THRESHOLD=$(jq -r '.thresholds.compression_trigger // 5' "$INDEX_FILE")
SKILL_THRESHOLD=$(jq -r '.thresholds.skillification_stability // 3' "$INDEX_FILE")
GUARD_THRESHOLD=$(jq -r '.thresholds.guardrail_consolidation // 3' "$INDEX_FILE")

TOTAL=$(echo "$COUNTS" | jq '[.[] | numbers] | add // 0')

# 태그 알림
TAG_ALERTS=$(echo "$TAG_INDEX" | jq --argjson thr "$THRESHOLD" \
    '[to_entries[] | select(.value >= $thr) | {level: "compression", tag: .key, count: .value, message: "태그 \(.key)의 자산이 \(.value)건 — 압축을 권장합니다"}]')

# stability 기반 스킬화 후보 (patterns, snippets에서 — 파일 접근 필요)
SKILL_ALERTS="[]"
for folder in patterns snippets; do
    dir="$ASSET_BASE/$folder"
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.md; do
        [[ -f "$f" ]] || continue
        stability=$(grep -E 'stability:' "$f" 2>/dev/null | head -1 | sed 's/.*stability:[[:space:]]*//' || echo "0")
        [[ -z "$stability" ]] && stability="0"
        if [[ "$stability" -ge "$SKILL_THRESHOLD" ]]; then
            SKILL_ALERTS=$(echo "$SKILL_ALERTS" | jq --arg f "$(basename "$f")" --argjson s "$stability" \
                '. + [{level: "skillification", file: $f, stability: $s, message: "stability \($s) 도달 — 스킬화를 권장합니다"}]')
        fi
    done
done

# guardrail 통합 후보
GUARD_ALERTS="[]"
GUARD_COUNT=$(echo "$COUNTS" | jq '.guardrails // 0')
if [[ "$GUARD_COUNT" -ge "$GUARD_THRESHOLD" ]]; then
    GUARD_ALERTS=$(jq -n --argjson c "$GUARD_COUNT" --argjson t "$GUARD_THRESHOLD" \
        '[{level: "guardrail_consolidation", count: $c, message: "가드레일이 \($c)건 축적됨 — 통합 정리를 권장합니다"}]')
fi

ALL_ALERTS=$(jq -n --argjson t "$TAG_ALERTS" --argjson s "$SKILL_ALERTS" --argjson g "$GUARD_ALERTS" '$t + $s + $g')

# --- 출력 ---
if [[ "$FORMAT" == "json" ]]; then
    jq -n --arg status "checked" \
          --argjson counts "$COUNTS" \
          --argjson total "$TOTAL" \
          --argjson tag_index "$TAG_INDEX" \
          --argjson alerts "$ALL_ALERTS" \
          '{status: $status, counts: $counts, total: $total, tag_index: $tag_index, alerts: $alerts}'
else
    echo "=== 증강자산 현황 (총 ${TOTAL}건) ==="
    echo ""
    echo "$COUNTS" | jq -r 'to_entries[] | "  \(.key): \(.value)건"'

    TAG_COUNT=$(echo "$TAG_INDEX" | jq 'length')
    if [[ "$TAG_COUNT" -gt 0 ]]; then
        echo ""
        echo "--- 태그별 ---"
        echo "$TAG_INDEX" | jq -r --argjson thr "$THRESHOLD" \
            'to_entries | sort_by(-.value)[] | "  #\(.key): \(.value)건\(if .value >= $thr then " ⚠ 압축 권장" else "" end)"'
    fi

    ALERT_COUNT=$(echo "$ALL_ALERTS" | jq 'length')
    echo ""
    if [[ "$ALERT_COUNT" -gt 0 ]]; then
        echo "알림 (${ALERT_COUNT}건):"
        echo "$ALL_ALERTS" | jq -r '.[] | "  [\(.level)] \(.message)"'
    else
        echo "임계치 미도달 — 현재 알림 없음"
    fi
fi
