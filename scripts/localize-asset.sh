#!/usr/bin/env bash
# localize-asset.sh — 범용(generic) 자산을 프로젝트/팀 맥락에 맞게 구체화한다.
#
# Layer: L2 (Operation)
# 의존: common.sh (L1)
# 규칙: L1만 source 가능. 단일 자산 변환.
#
# 2단계 프로세스:
#   1단계 (이 스크립트): 원본 복사 + 구체화 프롬프트 생성
#   2단계 (Claude): 프롬프트를 보고 실제 구체화 수행
#
# 원본은 보존된다 (비파괴적). 구체화된 버전은 별도 파일로 생성.
#
# 사용법:
#   localize-asset.sh --source <path> --project-context "React + TypeScript 모노레포" --base-dir _base/assets
#   localize-asset.sh --source <path> --context-file ./project-context.md --base-dir _base/assets
#   localize-asset.sh --source <path> --scope team --team-context "백엔드 팀, Go 기반" --base-dir _base/assets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ASSET_BASE="$(resolve_base_dir)"

SOURCE="" PROJECT_CONTEXT="" CONTEXT_FILE="" TARGET_SCOPE="project"

while [[ $# -gt 0 ]]; do
    case $1 in
        --source)          SOURCE="$2"; shift 2;;
        --project-context) PROJECT_CONTEXT="$2"; shift 2;;
        --team-context)    PROJECT_CONTEXT="$2"; TARGET_SCOPE="team"; shift 2;;
        --context-file)    CONTEXT_FILE="$2"; shift 2;;
        --scope)           TARGET_SCOPE="$2"; shift 2;;
        --base-dir)        ASSET_BASE="$2"; shift 2;;
        *) shift;;
    esac
done

# --- 검증 ---
if [[ -z "$SOURCE" || ! -f "$SOURCE" ]]; then
    echo '{"status":"error","reason":"--source 파일이 필요합니다"}' >&2
    exit 1
fi

if [[ -n "$CONTEXT_FILE" && -f "$CONTEXT_FILE" ]]; then
    PROJECT_CONTEXT=$(cat "$CONTEXT_FILE")
fi

if [[ -z "$PROJECT_CONTEXT" ]]; then
    echo '{"status":"error","reason":"--project-context 또는 --context-file로 프로젝트 맥락을 제공해야 합니다"}' >&2
    exit 1
fi

# --- 원본 메타데이터 추출 (frontmatter만) ---
FRONTMATTER=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$SOURCE")
ORIG_TYPE=$(get_field "$FRONTMATTER" "type")
[[ -z "$ORIG_TYPE" ]] && ORIG_TYPE="unknown"
ORIG_SCOPE=$(get_field "$FRONTMATTER" "scope")
[[ -z "$ORIG_SCOPE" ]] && ORIG_SCOPE="generic"
ORIG_TAGS=$(get_tags "$FRONTMATTER")

# scope 방향 검증: generic → project/team 만 허용
if [[ "$ORIG_SCOPE" == "project" && "$TARGET_SCOPE" == "project" ]]; then
    echo '{"status":"skip","reason":"이미 project scope입니다. abstract-asset.sh로 먼저 범용화한 뒤 다시 구체화하세요."}' >&2
    exit 0
fi

# --- 본문 추출 ---
BODY=$(parse_body "$SOURCE")

# --- 출력 파일 생성 ---
DATE=$(date +"%Y-%m-%d")
SOURCE_BASENAME=$(basename "$SOURCE" .md)
_type_subdir() {
    local t="$1"
    if [[ "$t" == "failure" ]]; then echo "failures"
    elif [[ "$t" == "pattern" ]]; then echo "patterns"
    elif [[ "$t" == "guardrail" ]]; then echo "guardrails"
    elif [[ "$t" == "snippet" ]]; then echo "snippets"
    elif [[ "$t" == "decision" ]]; then echo "decisions"
    elif [[ "$t" == "compressed" ]]; then echo ".compressed"
    else echo "patterns"
    fi
}
OUTPUT_DIR="$ASSET_BASE/$(_type_subdir "$ORIG_TYPE")"
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="$OUTPUT_DIR/${DATE}-local-${SOURCE_BASENAME}.md"
COUNTER=1
while [[ -f "$OUTPUT_FILE" ]]; do
    OUTPUT_FILE="$OUTPUT_DIR/${DATE}-local-${SOURCE_BASENAME}-${COUNTER}.md"
    ((COUNTER++))
done

# --- 새 frontmatter 생성 (scope 변경, 출처 추가) ---
# 원본 frontmatter를 복사하되 scope만 변경
NEW_FRONTMATTER=$(echo "$FRONTMATTER" | sed "s/^scope:.*/scope: ${TARGET_SCOPE}/")
# scope 필드가 없었으면 추가
if ! echo "$NEW_FRONTMATTER" | grep -q "^scope:"; then
    NEW_FRONTMATTER="${NEW_FRONTMATTER}
scope: ${TARGET_SCOPE}"
fi
# 출처 링크 추가
NEW_FRONTMATTER="${NEW_FRONTMATTER}
localized_from: \"$(basename "$SOURCE")\""

{
    echo "---"
    echo "$NEW_FRONTMATTER"
    echo "---"
    echo ""
    echo "## TODO: 에이전트 구체화 필요"
    echo ""
    echo "아래 범용 자산을 다음 프로젝트 맥락에 맞게 구체화하세요:"
    echo ""
    echo "### 프로젝트 맥락"
    echo ""
    echo "$PROJECT_CONTEXT"
    echo ""
    echo "### 구체화 지침"
    echo ""
    echo "1. **용어 매핑**: 범용 용어를 프로젝트의 구체적 기술/도구명으로 변환"
    echo "2. **경로·설정 구체화**: 추상적 경로를 실제 프로젝트 경로·설정값으로 교체"
    echo "3. **예시 추가**: 프로젝트에서 실제로 발생할 수 있는 구체적 시나리오 추가"
    echo "4. **가드레일 맥락화**: 범용 규칙을 팀/프로젝트의 구체적 제약으로 표현"
    echo "5. **범용 원본 보존**: 원본의 핵심 인사이트는 유지하되 맥락만 추가"
    echo ""
    echo "구체화가 완료되면 이 TODO 섹션을 삭제하세요."
    echo ""
    echo "---"
    echo ""
    echo "## 원본 (${ORIG_SCOPE} scope)"
    echo ""
    echo "$BODY"
} > "$OUTPUT_FILE"

jq -n \
    --arg status "localize_ready" \
    --arg source "$(basename "$SOURCE")" \
    --arg output "$OUTPUT_FILE" \
    --arg orig_scope "$ORIG_SCOPE" \
    --arg target_scope "$TARGET_SCOPE" \
    --arg orig_type "$ORIG_TYPE" \
    '{status: $status, source: $source, output: $output, direction: ($orig_scope + " → " + $target_scope), type: $orig_type, next_step: "출력 파일의 TODO 섹션을 따라 구체화를 수행하세요"}'
