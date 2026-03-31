#!/usr/bin/env bash
# abstract-asset.sh — 프로젝트/팀 특정 자산을 범용(generic)으로 추상화한다.
#
# 2단계 프로세스:
#   1단계 (이 스크립트): 원본 복사 + 추상화 프롬프트 생성 + 프로젝트 특정 요소 사전 감지
#   2단계 (Claude): 프롬프트를 보고 실제 추상화 수행
#
# 원본은 보존된다 (비파괴적). 추상화된 버전은 별도 파일로 생성.
#
# 사용법:
#   abstract-asset.sh --source <path> --base-dir _base/assets
#   abstract-asset.sh --source <path> --keep-original --base-dir _base/assets  # 원본도 유지 (기본)
#   abstract-asset.sh --source <path> --replace --base-dir _base/assets        # 원본을 추상화 버전으로 대체

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

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

SOURCE="" REPLACE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --source)        SOURCE="$2"; shift 2;;
        --replace)       REPLACE=true; shift;;
        --keep-original) REPLACE=false; shift;;
        --base-dir)      ASSET_BASE="$2"; shift 2;;
        *) shift;;
    esac
done

# --- 검증 ---
if [[ -z "$SOURCE" || ! -f "$SOURCE" ]]; then
    echo '{"status":"error","reason":"--source 파일이 필요합니다"}' >&2
    exit 1
fi

# --- frontmatter 추출 ---
FRONTMATTER=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$SOURCE")
ORIG_TYPE=$(get_field "$FRONTMATTER" "type")
[[ -z "$ORIG_TYPE" ]] && ORIG_TYPE="unknown"
ORIG_SCOPE=$(get_field "$FRONTMATTER" "scope")
[[ -z "$ORIG_SCOPE" ]] && ORIG_SCOPE="project"

# scope 방향 검증
if [[ "$ORIG_SCOPE" == "generic" ]]; then
    echo '{"status":"skip","reason":"이미 generic scope입니다. localize-asset.sh로 구체화하세요."}' >&2
    exit 0
fi

# --- 본문 추출 ---
BODY=$(parse_body "$SOURCE")

# ═══════════════════════════════════════════════════════════
# 프로젝트 특정 요소 자동 감지
# ═══════════════════════════════════════════════════════════
# quality-gate.sh와 동일한 패턴 + 추가 감지
DETECTED_SPECIFICS=""

# 1) 절대 경로
abs_paths=$(echo "$BODY" | { grep -oE '(/Users/[^ ]+|/home/[^ ]+|/var/[^ ]+|C:\\[^ ]+)' || true; } | head -5)
if [[ -n "$abs_paths" ]]; then
    DETECTED_SPECIFICS="${DETECTED_SPECIFICS}### 감지된 절대 경로\n\`\`\`\n${abs_paths}\n\`\`\`\n\n"
fi

# 2) localhost/IP
local_refs=$(echo "$BODY" | { grep -oE '(localhost:[0-9]+|127\.0\.0\.[0-9]+:[0-9]+|0\.0\.0\.0:[0-9]+)' || true; } | head -5)
if [[ -n "$local_refs" ]]; then
    DETECTED_SPECIFICS="${DETECTED_SPECIFICS}### 감지된 로컬 주소\n\`\`\`\n${local_refs}\n\`\`\`\n\n"
fi

# 3) 특정 버전 번호 (x.y.z 패턴)
versions=$(echo "$BODY" | { grep -oE '[a-zA-Z]+[- ]v?[0-9]+\.[0-9]+(\.[0-9]+)?' || true; } | head -5)
if [[ -n "$versions" ]]; then
    DETECTED_SPECIFICS="${DETECTED_SPECIFICS}### 감지된 특정 버전\n\`\`\`\n${versions}\n\`\`\`\n\n"
fi

# 4) 환경변수 (프로젝트 특정)
env_vars=$(echo "$BODY" | { grep -oE '\$\{?[A-Z_]{3,}[A-Z0-9_]*\}?' || true; } | sort -u | head -10)
if [[ -n "$env_vars" ]]; then
    DETECTED_SPECIFICS="${DETECTED_SPECIFICS}### 감지된 환경변수\n\`\`\`\n${env_vars}\n\`\`\`\n\n"
fi

# 5) URL (프로젝트 특정 도메인)
urls=$(echo "$BODY" | { grep -oE 'https?://[^ ]+' || true; } | { grep -v 'example\.com\|github\.com/docs\|stackoverflow\.com' || true; } | head -5)
if [[ -n "$urls" ]]; then
    DETECTED_SPECIFICS="${DETECTED_SPECIFICS}### 감지된 특정 URL\n\`\`\`\n${urls}\n\`\`\`\n\n"
fi

HAS_SPECIFICS="none"
[[ -n "$DETECTED_SPECIFICS" ]] && HAS_SPECIFICS="detected"

# --- 출력 파일 결정 ---
DATE=$(date +"%Y-%m-%d")
SOURCE_BASENAME=$(basename "$SOURCE" .md)

if $REPLACE; then
    OUTPUT_FILE="$SOURCE"
else
    OUTPUT_DIR="$(dirname "$SOURCE")"
    OUTPUT_FILE="$OUTPUT_DIR/${DATE}-abstract-${SOURCE_BASENAME}.md"
    COUNTER=1
    while [[ -f "$OUTPUT_FILE" ]]; do
        OUTPUT_FILE="$OUTPUT_DIR/${DATE}-abstract-${SOURCE_BASENAME}-${COUNTER}.md"
        ((COUNTER++))
    done
fi

# --- 새 frontmatter 생성 ---
NEW_FRONTMATTER=$(echo "$FRONTMATTER" | sed "s/^scope:.*/scope: generic/")
if ! echo "$NEW_FRONTMATTER" | grep -q "^scope:"; then
    NEW_FRONTMATTER="${NEW_FRONTMATTER}
scope: generic"
fi
NEW_FRONTMATTER="${NEW_FRONTMATTER}
abstracted_from: \"$(basename "$SOURCE")\""

{
    echo "---"
    echo "$NEW_FRONTMATTER"
    echo "---"
    echo ""
    echo "## TODO: 에이전트 추상화 필요"
    echo ""
    echo "아래 프로젝트 특정 자산을 범용 패턴으로 추상화하세요:"
    echo ""
    echo "### 추상화 지침"
    echo ""
    echo "1. **경로·이름 제거**: 절대 경로, 프로젝트명, 팀명 등을 일반적 설명으로 대체"
    echo "2. **기술 일반화**: 특정 프레임워크/라이브러리 이름을 범주로 추상화 (예: 'Next.js' → 'SSR 프레임워크')"
    echo "3. **패턴 추출**: 프로젝트 고유 사례에서 범용 원칙을 추출"
    echo "4. **맥락 유지**: 왜 이 패턴이 유효한지의 근거는 보존 (핵심 인사이트 훼손 금지)"
    echo "5. **적용 조건 명시**: 이 패턴이 유효한 전제 조건을 명확히 기술"
    echo ""
    if [[ -n "$DETECTED_SPECIFICS" ]]; then
        echo "### 자동 감지된 프로젝트 특정 요소"
        echo ""
        echo "아래 항목들이 프로젝트 특정 요소로 감지되었습니다. 추상화 시 우선 처리하세요:"
        echo ""
        echo -e "$DETECTED_SPECIFICS"
    fi
    echo "추상화가 완료되면 이 TODO 섹션을 삭제하세요."
    echo ""
    echo "---"
    echo ""
    echo "## 원본 (${ORIG_SCOPE} scope)"
    echo ""
    echo "$BODY"
} > "$OUTPUT_FILE"

jq -n \
    --arg status "abstract_ready" \
    --arg source "$(basename "$SOURCE")" \
    --arg output "$OUTPUT_FILE" \
    --arg orig_scope "$ORIG_SCOPE" \
    --arg detected "$HAS_SPECIFICS" \
    --argjson replace "$REPLACE" \
    '{status: $status, source: $source, output: $output, direction: ($orig_scope + " → generic"), detected_specifics: $detected, replace_original: $replace, next_step: "출력 파일의 TODO 섹션을 따라 추상화를 수행하세요"}'
