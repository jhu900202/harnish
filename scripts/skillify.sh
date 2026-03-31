#!/usr/bin/env bash
# skillify.sh — 압축된 자산 또는 고 stability 패턴을 기반으로 스킬 초안을 생성한다.
#
# 사용법:
#   skillify.sh --source /path/to/compressed.md --skill-name my-skill
#   skillify.sh --source /path/to/compressed.md --skill-name my-skill --output-dir /path
#
# v0 설계 메모:
#   - guardrail 추출: archive glob 대신 압축 본문에서 직접 추출 (경로 안정성)
#   - 압축 문서의 summarized 상태 확인 → 미요약이면 경고
#   - 출력 디렉토리 폴백 안정화

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SOURCE="" SKILL_NAME="" OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --source)     SOURCE="$2"; shift 2;;
        --skill-name) SKILL_NAME="$2"; shift 2;;
        --output-dir) OUTPUT_DIR="$2"; shift 2;;
        *) shift;;
    esac
done

if [[ -z "$SOURCE" || -z "$SKILL_NAME" ]]; then
    echo '{"status":"error","reason":"--source와 --skill-name은 필수"}'
    exit 1
fi

if [[ ! -f "$SOURCE" ]]; then
    echo "{\"status\":\"error\",\"reason\":\"소스 파일을 찾을 수 없습니다: $SOURCE\"}"
    exit 1
fi

# output-dir 기본값
if [[ -z "$OUTPUT_DIR" ]]; then
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        OUTPUT_DIR="$CLAUDE_PROJECT_DIR"
    else
        # harnish repo 기준 상위 디렉토리
        OUTPUT_DIR="$(cd "$SCRIPT_DIR/.." && cd .. && pwd)"
    fi
fi

DATE=$(date +"%Y-%m-%d")
SKILL_DIR="$OUTPUT_DIR/$SKILL_NAME"

mkdir -p "$SKILL_DIR/references"

# --- frontmatter에서 메타데이터 추출 ---
FRONTMATTER=$(parse_frontmatter "$SOURCE")

TAGS=$(get_tags "$FRONTMATTER")
[[ -z "$TAGS" ]] && TAGS="$SKILL_NAME"
TAGS=$(echo "$TAGS" | tr -d '"' | tr -d "'" | xargs)

LABEL=$(get_field "$FRONTMATTER" "label")
[[ -z "$LABEL" ]] && LABEL="압축 자산"
SOURCE_COUNT=$(get_field "$FRONTMATTER" "source_count")
[[ -z "$SOURCE_COUNT" ]] && SOURCE_COUNT="?"
SUMMARIZED=$(get_field "$FRONTMATTER" "summarized")
[[ -z "$SUMMARIZED" ]] && SUMMARIZED="unknown"

# --- 본문 추출 (frontmatter 제외) ---
BODY=$(parse_body "$SOURCE")

# --- guardrail 섹션 자동 추출 ---
# 전략: archive glob 대신 압축 본문에서 직접 추출 (경로 문제 회피)
#   1) 본문에서 guardrail/규칙/금지 관련 섹션 찾기
#   2) 없으면 안내 문구

GUARDRAIL_SECTION=""

# 본문에서 guardrail 관련 헤딩이 있는 섹션 추출
# ### 또는 ## 수준에서 guardrail, guard, 규칙, 금지 포함 헤딩
while IFS= read -r line; do
    GUARDRAIL_SECTION="${GUARDRAIL_SECTION}${line}
"
done < <(echo "$BODY" | awk '
    /^#{2,3} .*([Gg]uardrail|[Gg]uard|규칙|금지|제약|위반)/ { capture=1 }
    capture && /^#{2,3} / && !/([Gg]uardrail|[Gg]uard|규칙|금지|제약|위반)/ { capture=0 }
    capture { print }
' 2>/dev/null || true)

GUARDRAIL_SECTION=$(echo "$GUARDRAIL_SECTION" | sed '/^$/d' | head -100)

if [[ -z "$GUARDRAIL_SECTION" ]]; then
    GUARDRAIL_SECTION="(이 스킬에 적용할 가드레일이 있으면 여기에 정리하세요)"
fi

# --- 요약 상태 경고 ---
SUMMARY_WARNING=""
if [[ "$SUMMARIZED" == "false" ]]; then
    SUMMARY_WARNING="

> **경고**: 이 스킬의 소스는 아직 요약되지 않은 압축 문서입니다.
> 스킬화 전에 압축 문서를 먼저 요약(중복 제거·일반화)하는 것을 권장합니다.
"
fi

# --- SKILL.md 생성 ---
cat > "$SKILL_DIR/SKILL.md" << SKILLEOF
---
name: ${SKILL_NAME}
version: 0.0.1
description: >
  (자동 생성 초안) ${LABEL} 기반 스킬 — ${SOURCE_COUNT}건의 자산에서 추출.
  TRIGGERS: ${TAGS}.
  이 스킬은 증강자산 시스템에 의해 자동 생성되었으며, 검토·수정이 필요합니다.
---

# ${SKILL_NAME}

> 자동 생성일: ${DATE}
> 소스: $(basename "$SOURCE")  (${SOURCE_COUNT}건 압축)
> 태그: ${TAGS}
${SUMMARY_WARNING}
## 개요

(여기에 이 스킬이 무엇을 하는지 한 문단으로 설명하세요)

## 축적된 지식

${BODY}

## 가드레일

${GUARDRAIL_SECTION}

## 참고

- 이 스킬은 자동 생성된 초안입니다
- 반드시 검토 후 필요 없는 부분을 제거하세요
- 원본 자산은 \`references/\` 디렉토리에 보관됩니다
- skill-creator 스킬로 description 최적화 및 테스트가 가능합니다
SKILLEOF

# 소스를 references에 복사
cp "$SOURCE" "$SKILL_DIR/references/source-$(basename "$SOURCE")"

# --- 결과 출력 ---
FILES_JSON=$(jq -n --arg s "$SKILL_DIR/SKILL.md" --arg r "$SKILL_DIR/references/source-$(basename "$SOURCE")" '[$s, $r]')
jq -n --arg status "skill_draft_created" \
      --arg name "$SKILL_NAME" \
      --arg dir "$SKILL_DIR" \
      --arg summarized "$SUMMARIZED" \
      --argjson files "$FILES_JSON" \
      --argjson next '["SKILL.md의 개요와 description을 작성하세요","가드레일 섹션을 검토하세요","skill-creator로 description을 최적화하세요"]' \
      '{status: $status, skill_name: $name, skill_dir: $dir, source_summarized: $summarized, files: $files, next_steps: $next}'
