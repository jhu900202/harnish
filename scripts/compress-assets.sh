#!/usr/bin/env bash
# compress-assets.sh — 임계치에 도달한 자산을 압축한다.
#
# Layer: L3 (Aggregate)
# 의존: common.sh (L1)
# 규칙: L1 source 가능, L2 호출 가능. 다중 자산 분석·변환.
#
# "압축"의 의미:
#   1단계 (이 스크립트): 원본을 수집 → 아카이브 → 병합 문서 생성 + 요약 프롬프트 포함
#   2단계 (Claude): 병합 문서의 "TODO: 요약" 프롬프트를 보고 중복 제거·요약·일반화 수행
#
#   스크립트 단독으로는 "진정한 압축"이 불가하다 (LLM이 필요).
#   그래서 스크립트는 원본을 안전하게 아카이브하고, Claude에게 요약을 요청하는
#   구조화된 문서를 생성하는 데 집중한다.
#
# v0 설계 메모:
#   - 철학 일관성: concat이 아닌 "요약 요청" 문서 생성
#   - 인덱스 갱신: atomic write (일괄 차감 후 한 번에 쓰기)
#   - 태그 매칭: 따옴표 포함된 YAML 태그도 매칭
#   - 환경변수 안정화
#
# 사용법:
#   compress-assets.sh --tag api           # 특정 태그 압축
#   compress-assets.sh --type failures     # 특정 유형 압축
#   compress-assets.sh --all               # 임계치 도달 태그 전부 압축

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ASSET_BASE="$(resolve_base_dir)"
TAG="" TYPE="" ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)      TAG="$2"; shift 2;;
        --type)     TYPE="$2"; shift 2;;
        --all)      ALL=true; shift;;
        --base-dir) ASSET_BASE="$2"; shift 2;;
        *) shift;;
    esac
done

DATE=$(date +"%Y-%m-%d")

# --- 태그로 자산 찾기 (따옴표 포함 태그도 매칭) ---
find_by_tag() {
    local tag="$1"
    local results=()
    for folder in patterns failures guardrails snippets decisions; do
        local dir="$ASSET_BASE/$folder"
        [[ -d "$dir" ]] || continue
        for f in "$dir"/*.md; do
            [[ -f "$f" ]] || continue
            # tags: ["api", "retry"] 또는 tags: [api, retry] 둘 다 매칭
            # 따옴표 유무, 공백 유무 모든 조합을 커버
            if grep -qE "tags:.*\[" "$f" 2>/dev/null && grep -E "tags:" "$f" | grep -qw "$tag" 2>/dev/null; then
                results+=("$f")
            fi
        done
    done
    [[ ${#results[@]} -eq 0 ]] && return 1
    printf '%s\n' "${results[@]}"
}

# --- 압축 실행 ---
compress_group() {
    local label="$1"
    shift
    local files=("$@")
    local count=${#files[@]}

    [[ $count -eq 0 ]] && return

    local archive_dir="$ASSET_BASE/.archive/${DATE}-${label}"
    local compressed_dir="$ASSET_BASE/.compressed"
    mkdir -p "$archive_dir" "$compressed_dir"

    # 모든 태그 수집 (따옴표 제거 후 정규화)
    local all_tags=""
    for f in "${files[@]}"; do
        local fm_temp
        fm_temp=$(parse_frontmatter "$f")
        local tags_line
        tags_line=$(get_tags "$fm_temp")
        [[ -n "$tags_line" ]] && all_tags="$all_tags,$tags_line"
    done
    all_tags=$(echo "$all_tags" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | tr -d '"' | tr -d "'" | grep -v '^$' | sort -u | paste -sd, -)

    # YAML 태그 포맷 (따옴표 포함)
    local yaml_tags=""
    IFS=',' read -ra tag_items <<< "$all_tags"
    for item in "${tag_items[@]}"; do
        item=$(echo "$item" | xargs)
        [[ -z "$item" ]] && continue
        if [[ -n "$yaml_tags" ]]; then
            yaml_tags="${yaml_tags}, \"${item}\""
        else
            yaml_tags="\"${item}\""
        fi
    done

    # 압축 문서 생성 — 원본 본문 + Claude에게 요약 요청
    local output="$compressed_dir/${DATE}-${label}.md"
    {
        echo "---"
        echo "type: compressed"
        echo "date: $DATE"
        echo "label: \"$label\""
        echo "source_count: $count"
        echo "tags: [${yaml_tags}]"
        echo "summarized: false"
        echo "---"
        echo ""
        echo "# 압축 자산: $label"
        echo ""
        echo "원본 ${count}건을 수집. 원본은 \`.archive/${DATE}-${label}/\`에 보관."
        echo ""
        echo "---"
        echo ""
        echo "## TODO: 에이전트 요약 필요"
        echo ""
        echo "아래 원본 자산들을 읽고 다음을 수행하세요:"
        echo ""
        echo "1. **중복 제거**: 같은 문제·해결법이 반복되면 하나로 병합"
        echo "2. **일반화**: 프로젝트 특정 세부사항을 제거하고 범용 패턴으로 추상화"
        echo "3. **구조화**: 핵심 인사이트를 3~7개의 명확한 항목으로 정리"
        echo "4. **가드레일 추출**: 금지사항·제약이 있으면 별도 섹션으로 분리"
        echo ""
        echo "요약이 완료되면 이 TODO 섹션을 삭제하고 frontmatter의 \`summarized: false\`를 \`true\`로 변경하세요."
        echo ""
        echo "---"
        echo ""
        echo "## 원본 자산"
        echo ""

        for f in "${files[@]}"; do
            local fname=$(basename "$f" .md)
            local fmtmp
            fmtmp=$(parse_frontmatter "$f")
            local ftype
            ftype=$(get_field "$fmtmp" "type")
            [[ -z "$ftype" ]] && ftype="unknown"
            local fcontext
            fcontext=$(get_field "$fmtmp" "context")
            echo "### ${fname} (${ftype})"
            [[ -n "$fcontext" ]] && echo "> context: ${fcontext}"
            echo ""
            # frontmatter 제거 후 본문만 추출 (common.sh: parse_body)
            parse_body "$f" | grep -v '(미정)' || true
            echo ""
            echo "---"
            echo ""
        done
    } > "$output"

    # 원본을 아카이브로 이동
    for f in "${files[@]}"; do
        mv "$f" "$archive_dir/" 2>/dev/null || cp "$f" "$archive_dir/"
    done

    # 인덱스 갱신: 일괄 차감 후 atomic write
    local INDEX_FILE="$ASSET_BASE/.meta/index.json"
    if [[ -f "$INDEX_FILE" ]]; then
        local updated
        updated=$(cat "$INDEX_FILE")

        for f in "${files[@]}"; do
            local archived_file="$archive_dir/$(basename "$f")"
            local afm
            afm=$(parse_frontmatter "$archived_file")
            local ftype
            ftype=$(get_field "$afm" "type")

            # counts 차감
            case "$ftype" in
                pattern)   updated=$(echo "$updated" | jq '.counts.patterns = ([(.counts.patterns // 0) - 1, 0] | max)');;
                failure)   updated=$(echo "$updated" | jq '.counts.failures = ([(.counts.failures // 0) - 1, 0] | max)');;
                guardrail) updated=$(echo "$updated" | jq '.counts.guardrails = ([(.counts.guardrails // 0) - 1, 0] | max)');;
                snippet)   updated=$(echo "$updated" | jq '.counts.snippets = ([(.counts.snippets // 0) - 1, 0] | max)');;
                decision)  updated=$(echo "$updated" | jq '.counts.decisions = ([(.counts.decisions // 0) - 1, 0] | max)');;
                *)         continue;;
            esac

            # tag_index 차감
            local ftags
            ftags=$(get_tags "$afm")
            if [[ -n "$ftags" ]]; then
                IFS=',' read -ra ftag_arr <<< "$ftags"
                for ft in "${ftag_arr[@]}"; do
                    ft=$(echo "$ft" | xargs | tr -d '"' | tr -d "'")
                    [[ -z "$ft" ]] && continue
                    updated=$(echo "$updated" | jq --arg t "$ft" \
                        '.tag_index[$t] = ([(.tag_index[$t] // 0) - 1, 0] | max) | if .tag_index[$t] == 0 then del(.tag_index[$t]) else . end')
                done
            fi
        done

        # atomic write (common.sh)
        atomic_write_index "$INDEX_FILE" "$updated"
    fi

    echo "{\"label\": \"$label\", \"count\": $count, \"output\": \"$output\", \"needs_summary\": true}"
}

# --- 메인 ---
if [[ -n "$TAG" ]]; then
    FILES=()
    while IFS= read -r f; do [[ -n "$f" ]] && FILES+=("$f"); done < <(find_by_tag "$TAG")
    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "{\"status\":\"empty\",\"message\":\"태그 '$TAG'에 해당하는 자산이 없습니다.\"}"
        exit 0
    fi
    compress_group "tag-${TAG}" "${FILES[@]}"

elif [[ -n "$TYPE" ]]; then
    DIR="$ASSET_BASE/$TYPE"
    if [[ ! -d "$DIR" ]]; then
        echo "{\"status\":\"empty\",\"message\":\"유형 '$TYPE' 디렉토리가 없습니다.\"}"
        exit 0
    fi
    FILES=()
    while IFS= read -r f; do [[ -n "$f" ]] && FILES+=("$f"); done < <(find "$DIR" -maxdepth 1 -name '*.md' -type f)
    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "{\"status\":\"empty\",\"message\":\"유형 '$TYPE'에 해당하는 자산이 없습니다.\"}"
        exit 0
    fi
    compress_group "type-${TYPE}" "${FILES[@]}"

elif $ALL; then
    INDEX_FILE="$ASSET_BASE/.meta/index.json"
    if [[ ! -f "$INDEX_FILE" ]]; then
        echo "{\"status\":\"error\",\"message\":\"인덱스 파일이 없습니다.\"}"
        exit 0
    fi

    THRESHOLD=$(jq -r '.thresholds.compression_trigger // 5' "$INDEX_FILE")
    RESULTS="[]"

    for tag in $(jq -r --argjson thr "$THRESHOLD" '.tag_index | to_entries[] | select(.value >= $thr) | .key' "$INDEX_FILE"); do
        FILES=()
        while IFS= read -r f; do [[ -n "$f" ]] && FILES+=("$f"); done < <(find_by_tag "$tag")
        if [[ ${#FILES[@]} -gt 0 ]]; then
            RESULT=$(compress_group "tag-${tag}" "${FILES[@]}")
            RESULTS=$(echo "$RESULTS" | jq --argjson r "[$RESULT]" '. + $r')
        fi
    done

    jq -n --argjson groups "$RESULTS" '{status: "compressed_all", compressed_groups: $groups, note: "각 압축 문서에 TODO: 에이전트 요약 필요 섹션이 있습니다. Claude에게 요약을 요청하세요."}'

else
    echo "사용법: compress-assets.sh --tag <tag> | --type <type> | --all"
    echo "  --base-dir <path>  자산 경로 지정"
    exit 1
fi
