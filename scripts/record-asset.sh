#!/usr/bin/env bash
# record-asset.sh — 자산을 마크다운 파일로 기록하고 인덱스를 갱신한다.
#
# 사용법:
#   # 짧은 기록
#   record-asset.sh --type pattern --tags "api,retry" --context "API 연동" \
#       --title "exponential-backoff" --content "지수 백오프 + 최대 3회 재시도"
#
#   # 상세 기록 (마크다운 파일로)
#   record-asset.sh --type failure --tags "docker,build" --context "Docker 빌드" \
#       --title "layer-cache-miss" --body-file /tmp/failure-detail.md
#
#   # stdin JSON
#   echo '{"type":"failure","tags":["api"],"title":"...","content":"..."}' | record-asset.sh --stdin
#
# v0 설계 메모:
#   - slugify: 비ASCII(한국어 등) 제목 지원 (md5 해시 폴백)
#   - YAML 태그: 각 태그를 따옴표로 감싸서 YAML 규격 준수
#   - 섹션 설정: references/sections.json에서 읽어 하드코딩 제거
#   - 환경변수: SCRIPT_DIR 기반 상대경로로 안정적 해석
#   - 인덱스 갱신: 임시파일 + mv로 atomic write

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
SKILL_DIR="$(cd "$SCRIPT_DIR/../skills/harnish" && pwd)"
SECTIONS_FILE="$SKILL_DIR/references/sections.json"

# --- 환경변수 해석: SCRIPT_DIR 기반 상대경로 우선 ---
# 우선순위: --base-dir 인자 > ASSET_BASE_DIR > CLAUDE_PROJECT_DIR/_base/assets > 스킬 기준 상대경로
_default_base() {
    if [[ -n "${ASSET_BASE_DIR:-}" ]]; then
        echo "$ASSET_BASE_DIR"
    elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        echo "${CLAUDE_PROJECT_DIR}/_base/assets"
    else
        # harnish repo 구조 기준: scripts/ → harnish/ → 상위
        local harnish_root
        harnish_root="$(cd "$SCRIPT_DIR/.." && pwd)"
        local parent
        parent="$(cd "$harnish_root/.." && pwd)"
        echo "$parent/_base/assets"
    fi
}
ASSET_BASE="$(_default_base)"

DATE=$(date +"%Y-%m-%d")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- 인자 파싱 ---
TYPE="" TAGS="" CONTEXT="" TITLE="" CONTENT="" BODY_FILE=""
SESSION_ID="manual" ENV_NAME="unknown" SCOPE="generic" STDIN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)       TYPE="$2"; shift 2;;
        --tags)       TAGS="$2"; shift 2;;
        --context)    CONTEXT="$2"; shift 2;;
        --title)      TITLE="$2"; shift 2;;
        --content)    CONTENT="$2"; shift 2;;
        --body-file)  BODY_FILE="$2"; shift 2;;
        --session-id) SESSION_ID="$2"; shift 2;;
        --env)        ENV_NAME="$2"; shift 2;;
        --scope)      SCOPE="$2"; shift 2;;
        --base-dir)   ASSET_BASE="$2"; shift 2;;
        --stdin)      STDIN=true; shift;;
        *) shift;;
    esac
done

if $STDIN; then
    INPUT=$(cat)
    TYPE=$(echo "$INPUT" | jq -r '.type // empty')
    TAGS=$(echo "$INPUT" | jq -r '(.tags // []) | join(",")')
    CONTEXT=$(echo "$INPUT" | jq -r '.context // ""')
    TITLE=$(echo "$INPUT" | jq -r '.title // ""')
    CONTENT=$(echo "$INPUT" | jq -r '.content // ""')
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "stdin"')
    ENV_NAME=$(echo "$INPUT" | jq -r '.environment // "unknown"')
    SCOPE=$(echo "$INPUT" | jq -r '.scope // "generic"')
fi

if [[ -z "$TYPE" || -z "$TITLE" ]]; then
    echo '{"status":"error","reason":"--type과 --title은 필수"}' >&2
    exit 1
fi

# scope 검증 (generic, project, team 만 허용)
case "$SCOPE" in
    generic|project|team) ;;
    *) echo "{\"status\":\"error\",\"reason\":\"--scope은 generic, project, team 중 하나여야 합니다 (got: $SCOPE)\"}"; exit 1;;
esac

# --- _base/assets/ 초기화 (없으면 자동 생성) ---
if [[ ! -d "$ASSET_BASE/.meta" ]]; then
    bash "$SCRIPT_DIR/init-assets.sh" --base-dir "$ASSET_BASE" --quiet
fi

# ═══════════════════════════════════════════════════════════
# 슬러그 생성 — 비ASCII 안전
# ═══════════════════════════════════════════════════════════
# 1차: ASCII 변환 시도 → 유효한 slug가 나오면 사용
# 2차: 비어있으면 (한국어 등) md5 해시 앞 12자를 slug로 사용
slugify() {
    local input="$1"
    # ASCII 문자만 추출하여 slug 시도
    local ascii_slug
    ascii_slug=$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-60)

    if [[ -n "$ascii_slug" && "$ascii_slug" != "-" ]]; then
        echo "$ascii_slug"
    else
        # 비ASCII 제목: md5 해시 앞 12자 사용
        local hash
        hash=$(echo -n "$input" | md5sum | cut -c1-12)
        echo "$hash"
    fi
}

SLUG=$(slugify "$TITLE")

# --- 폴더 매핑 ---
case "$TYPE" in
    pattern)   FOLDER="patterns";;
    failure)   FOLDER="failures";;
    guardrail) FOLDER="guardrails";;
    snippet)   FOLDER="snippets";;
    decision)  FOLDER="decisions";;
    *) echo "{\"status\":\"error\",\"reason\":\"unknown type: $TYPE\"}"; exit 1;;
esac

TYPE_DIR="$ASSET_BASE/$FOLDER"
mkdir -p "$TYPE_DIR"

# --- 파일명 (충돌 방지) ---
FILENAME="${DATE}-${SLUG}.md"
FILEPATH="$TYPE_DIR/$FILENAME"
COUNTER=1
while [[ -f "$FILEPATH" ]]; do
    FILENAME="${DATE}-${SLUG}-${COUNTER}.md"
    FILEPATH="$TYPE_DIR/$FILENAME"
    ((COUNTER++))
done

# --- 본문 구성 ---
if [[ -n "$BODY_FILE" && -f "$BODY_FILE" ]]; then
    BODY_CONTENT=$(cat "$BODY_FILE")
elif [[ -n "$CONTENT" ]]; then
    BODY_CONTENT="$CONTENT"
else
    BODY_CONTENT=""
fi

# ═══════════════════════════════════════════════════════════
# YAML 태그 포맷 — 따옴표로 감싸서 YAML 규격 준수
# ═══════════════════════════════════════════════════════════
format_yaml_tags() {
    local raw="$1"
    if [[ -z "$raw" ]]; then
        echo "[]"
        return
    fi
    local result=""
    IFS=',' read -ra items <<< "$raw"
    for item in "${items[@]}"; do
        item=$(echo "$item" | xargs)  # trim
        [[ -z "$item" ]] && continue
        if [[ -n "$result" ]]; then
            result="${result}, \"${item}\""
        else
            result="\"${item}\""
        fi
    done
    echo "[${result}]"
}

YAML_TAGS=$(format_yaml_tags "$TAGS")

# ═══════════════════════════════════════════════════════════
# 템플릿 생성 — sections.json에서 읽거나 폴백
# ═══════════════════════════════════════════════════════════
generate_template() {
    local type="$1"
    if [[ -f "$SECTIONS_FILE" ]]; then
        local template_lines
        template_lines=$(jq -r --arg t "$type" '.[$t].template // [] | .[]' "$SECTIONS_FILE" 2>/dev/null || echo "")
        if [[ -n "$template_lines" ]]; then
            echo -e "$template_lines"
            return
        fi
    fi
    # sections.json이 없거나 해당 유형이 없으면 기본 템플릿
    case "$type" in
        failure)
            echo -e "## 표면 증상\n\n## 실제 원인\n\n## 해결 과정\n\n## 일반화된 패턴\n";;
        pattern)
            echo -e "## 적용 상황 (전제 조건)\n\n## 접근법\n\n## 왜 효과적인가\n\n## 적용 범위와 한계\n";;
        guardrail)
            echo -e "## 규칙\n\n## 이유\n\n## 위반 시 결과\n\n## 예외 조건\n";;
        snippet)
            echo -e "## 용도\n\n## 코드\n\n\`\`\`\n\`\`\`\n\n## 사용 예시\n";;
        decision)
            echo -e "## 결정 사항\n\n## 고려한 대안\n\n## 선택 근거\n\n## 유효 조건 (이 결정이 변할 수 있는 맥락)\n";;
    esac
}

# --- frontmatter + 본문 생성 ---
{
    echo "---"
    echo "type: ${TYPE}"
    echo "title: \"${TITLE}\""
    echo "date: ${DATE}"
    echo "context: \"${CONTEXT}\""
    echo "tags: ${YAML_TAGS}"
    case "$TYPE" in
        pattern|snippet)
            echo "stability: 1"
            ;;
        failure)
            echo "resolved: true"
            ;;
        guardrail)
            echo "level: soft"
            ;;
        decision)
            echo "confidence: medium"
            ;;
    esac
    echo "scope: ${SCOPE}"
    echo "source_session: \"${SESSION_ID}\""
    echo "environment: \"${ENV_NAME}\""
    echo "---"
    echo ""

    if [[ -n "$BODY_CONTENT" ]]; then
        echo "$BODY_CONTENT"
    else
        generate_template "$TYPE"
    fi
} > "$FILEPATH"

# ═══════════════════════════════════════════════════════════
# 인덱스 갱신 — atomic write (임시파일 + mv)
# ═══════════════════════════════════════════════════════════
INDEX_FILE="$ASSET_BASE/.meta/index.json"
if [[ -f "$INDEX_FILE" ]]; then
    IFS=',' read -ra TAG_ARRAY <<< "$TAGS"

    UPDATED=$(jq --arg folder "$FOLDER" \
        '.counts[$folder] = ((.counts[$folder] // 0) + 1)' "$INDEX_FILE")

    for tag in "${TAG_ARRAY[@]}"; do
        tag=$(echo "$tag" | xargs)
        [[ -z "$tag" ]] && continue
        UPDATED=$(echo "$UPDATED" | jq --arg t "$tag" \
            '.tag_index[$t] = ((.tag_index[$t] // 0) + 1)')
    done

    echo "$UPDATED" > "${INDEX_FILE}.tmp" && mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
fi

# --- 임계치 확인 ---
ALERTS="[]"
if [[ -f "$INDEX_FILE" ]]; then
    THRESHOLD=$(jq -r '.thresholds.compression_trigger // 5' "$INDEX_FILE")
    ALERTS=$(jq --argjson thr "$THRESHOLD" \
        '[.tag_index | to_entries[] | select(.value >= $thr) | {tag: .key, count: .value}]' \
        "$INDEX_FILE")
fi

# ═══════════════════════════════════════════════════════════
# RCA 셀프힐링: 기록 직후 자가검증 + 자동 수정
# ═══════════════════════════════════════════════════════════
RCA_WARNINGS="[]"
RCA_HEALED="[]"

# 1) frontmatter 필수 필드 검증
rca_check_frontmatter() {
    local file="$1"
    local fm
    fm=$(parse_frontmatter "$file")
    local tags_val
    tags_val=$(get_tags "$fm")
    if [[ -z "$tags_val" ]]; then
        RCA_WARNINGS=$(echo "$RCA_WARNINGS" | jq '. + ["tags가 비어있습니다 — 3~5개의 소문자 kebab-case 태그를 권장합니다"]')
    fi
    local ctx_val
    ctx_val=$(get_field "$fm" "context")
    if [[ -z "$ctx_val" ]]; then
        RCA_WARNINGS=$(echo "$RCA_WARNINGS" | jq '. + ["context가 비어있습니다 — 기록 배경을 넣으면 검색성이 올라갑니다"]')
    fi
}

# 2) 본문 필수 섹션 검증 — sections.json 기반
rca_check_body() {
    local file="$1" type="$2"
    local body
    body=$(parse_body "$file")

    # sections.json에서 필수 섹션 목록을 읽는다
    local required_sections=""
    local required_patterns=""
    if [[ -f "$SECTIONS_FILE" ]]; then
        required_sections=$(jq -r --arg t "$type" '.[$t].required_sections // [] | .[]' "$SECTIONS_FILE" 2>/dev/null || echo "")
        required_patterns=$(jq -r --arg t "$type" '.[$t].required_patterns // [] | .[]' "$SECTIONS_FILE" 2>/dev/null || echo "")
    fi

    # 섹션 검증
    if [[ -n "$required_sections" ]]; then
        while IFS= read -r sec; do
            [[ -z "$sec" ]] && continue
            if ! echo "$body" | grep -q "## ${sec}"; then
                RCA_WARNINGS=$(echo "$RCA_WARNINGS" | jq --arg s "$sec" '. + ["필수 섹션 누락: " + $s]')
            else
                # 섹션은 있지만 내용이 비어있는지
                local sec_content
                sec_content=$(echo "$body" | sed -n "/## ${sec}/,/## /p" | grep -v "^## " | grep -v "^$" || true)
                if [[ -z "$sec_content" ]]; then
                    RCA_WARNINGS=$(echo "$RCA_WARNINGS" | jq --arg s "$sec" '. + ["섹션 내용 비어있음: " + $s + " — 에이전트가 채워야 합니다"]')
                fi
            fi
        done <<< "$required_sections"
    fi

    # 패턴 검증 (snippet의 코드 블록 등)
    if [[ -n "$required_patterns" ]]; then
        while IFS= read -r pat; do
            [[ -z "$pat" ]] && continue
            if ! echo "$body" | grep -qF "$pat"; then
                RCA_WARNINGS=$(echo "$RCA_WARNINGS" | jq --arg p "$pat" '. + ["필수 패턴 누락: " + $p]')
            fi
        done <<< "$required_patterns"
    fi

    # 본문이 완전히 비어있으면 경고
    local body_lines
    body_lines=$(echo "$body" | { grep -v "^#" || true; } | { grep -v "^$" || true; } | { grep -v '```' || true; } | wc -l | xargs)
    if [[ "$body_lines" -eq 0 && -z "$BODY_CONTENT" && -z "$CONTENT" ]]; then
        RCA_WARNINGS=$(echo "$RCA_WARNINGS" | jq '. + ["본문이 비어있습니다 — 빈 템플릿만 기록됨. --body-file이나 --content로 내용을 채워주세요"]')
    fi
}

# 3) 자동 치유: date가 비어있으면 수정
rca_heal_date() {
    local file="$1"
    local file_date
    file_date=$(grep -E 'date:' "$file" 2>/dev/null | head -1 | sed 's/.*date:[[:space:]]*//' || echo "")
    if [[ -z "$file_date" ]]; then
        sed -i '' "s/^date:.*/date: ${DATE}/" "$file"
        RCA_HEALED=$(echo "$RCA_HEALED" | jq '. + ["date 필드가 비어있어 자동 설정: '"$DATE"'"]')
    fi
}

# 4) 자동 치유: 본문에 "(미정)" 문자열이 있으면 제거
rca_heal_placeholder() {
    local file="$1"
    if grep -q "(미정)" "$file" 2>/dev/null; then
        sed -i '' 's/(미정)//g' "$file"
        RCA_HEALED=$(echo "$RCA_HEALED" | jq '. + ["(미정) 플레이스홀더 자동 제거"]')
    fi
}

# RCA 실행
rca_check_frontmatter "$FILEPATH"
rca_check_body "$FILEPATH" "$TYPE"
rca_heal_date "$FILEPATH"
rca_heal_placeholder "$FILEPATH"

RCA_WARNING_COUNT=$(echo "$RCA_WARNINGS" | jq 'length')
RCA_HEALED_COUNT=$(echo "$RCA_HEALED" | jq 'length')

# --- 결과 ---
jq -n --arg status "recorded" \
      --arg file "$FILEPATH" \
      --arg type "$TYPE" \
      --arg tags "$TAGS" \
      --argjson alerts "$ALERTS" \
      --argjson rca_warnings "$RCA_WARNINGS" \
      --argjson rca_healed "$RCA_HEALED" \
      '{status: $status, file: $file, type: $type, tags: ($tags | split(",")),
        alerts: $alerts,
        rca: {warnings: $rca_warnings, healed: $rca_healed, quality: (if ($rca_warnings | length) == 0 then "good" elif ($rca_warnings | length) <= 2 then "fair" else "poor" end)}}'
