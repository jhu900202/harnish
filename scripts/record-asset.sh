#!/usr/bin/env bash
# record-asset.sh — 자산을 JSONL 파일에 1줄로 기록한다.
#
# Layer: L1 (Storage)
# 의존: common.sh (L1)
#
# 사용법:
#   record-asset.sh --type pattern --tags "api,retry" --title "exponential-backoff" --body "내용"
#   record-asset.sh --type failure --tags "docker,build" --title "cache-miss" --body-file /tmp/detail.md
#   echo '{"type":"failure","tags":["api"],"title":"...","body":"..."}' | record-asset.sh --stdin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE="$(resolve_base_dir)"
DATE=$(date +"%Y-%m-%d")

# --- 인자 파싱 ---
TYPE="" TAGS="" CONTEXT="" TITLE="" BODY="" BODY_FILE=""
SESSION_ID="manual" SCOPE="generic" STDIN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)       TYPE="$2"; shift 2;;
        --tags)       TAGS="$2"; shift 2;;
        --context)    CONTEXT="$2"; shift 2;;
        --title)      TITLE="$2"; shift 2;;
        --body)       BODY="$2"; shift 2;;
        --content)    BODY="$2"; shift 2;;
        --body-file)  BODY_FILE="$2"; shift 2;;
        --session-id) SESSION_ID="$2"; shift 2;;
        --scope)      SCOPE="$2"; shift 2;;
        --base-dir)   BASE="$2"; shift 2;;
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
    BODY=$(echo "$INPUT" | jq -r '.body // .content // ""')
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "stdin"')
    SCOPE=$(echo "$INPUT" | jq -r '.scope // "generic"')
fi

if [[ -z "$TYPE" || -z "$TITLE" ]]; then
    echo '{"status":"error","reason":"--type과 --title은 필수"}' >&2
    exit 1
fi

# type 검증
case "$TYPE" in
    failure|pattern|guardrail|snippet|decision) ;;
    *) echo "{\"status\":\"error\",\"reason\":\"unknown type: $TYPE\"}"; exit 1;;
esac

# --- .harnish/ 초기화 ---
if [[ ! -d "$BASE" ]]; then
    bash "$SCRIPT_DIR/init-assets.sh" --base-dir "$BASE" --quiet
fi

RAG_FILE="$BASE/harnish-rag.jsonl"

# --- 본문 ---
BODY_CONTENT="$BODY"
if [[ -n "$BODY_FILE" && -f "$BODY_FILE" ]]; then
    BODY_CONTENT=$(cat "$BODY_FILE")
fi

# --- 슬러그 ---
SLUG=$(slugify "$TITLE")

# --- 태그 배열 ---
TAG_JSON="[]"
if [[ -n "$TAGS" ]]; then
    TAG_JSON=$(echo "$TAGS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -s .)
fi

# --- JSON 레코드 구성 ---
RECORD=$(jq -n -c \
  --arg type "$TYPE" \
  --arg slug "$SLUG" \
  --arg title "$TITLE" \
  --argjson tags "$TAG_JSON" \
  --arg date "$DATE" \
  --arg scope "$SCOPE" \
  --arg body "$BODY_CONTENT" \
  --arg context "$CONTEXT" \
  --arg session "$SESSION_ID" \
  '{type:$type, slug:$slug, title:$title, tags:$tags, date:$date, scope:$scope, body:$body, context:$context, session:$session}')

# 타입별 선택 필드
case "$TYPE" in
  failure)         RECORD=$(echo "$RECORD" | jq -c '. + {resolved: true}');;
  pattern|snippet) RECORD=$(echo "$RECORD" | jq -c '. + {stability: 1}');;
  guardrail)       RECORD=$(echo "$RECORD" | jq -c '. + {level: "soft"}');;
  decision)        RECORD=$(echo "$RECORD" | jq -c '. + {confidence: "medium"}');;
esac

# --- append (atomic: copy + append + mv) ---
TMPRAG=$(mktemp "${RAG_FILE}.XXXXXX")
trap 'rm -f "$TMPRAG"' EXIT
cp "$RAG_FILE" "$TMPRAG"
echo "$RECORD" >> "$TMPRAG"
mv "$TMPRAG" "$RAG_FILE"

# --- RCA 검증 ---
RCA_WARNINGS=()
[[ -z "$CONTEXT" ]] && RCA_WARNINGS+=("context가 비어있습니다")
[[ -z "$BODY_CONTENT" ]] && RCA_WARNINGS+=("body가 비어있습니다")
[[ "$TAGS" == "" ]] && RCA_WARNINGS+=("tags가 비어있습니다")

RCA_QUALITY="good"
if [[ ${#RCA_WARNINGS[@]} -gt 2 ]]; then
    RCA_QUALITY="poor"
elif [[ ${#RCA_WARNINGS[@]} -gt 0 ]]; then
    RCA_QUALITY="fair"
fi

if [[ ${#RCA_WARNINGS[@]} -gt 0 ]]; then
    RCA_WARN_JSON=$(printf '%s\n' "${RCA_WARNINGS[@]}" | jq -R . | jq -s .)
else
    RCA_WARN_JSON="[]"
fi

# --- 결과 ---
jq -n -c \
  --arg status "recorded" \
  --arg type "$TYPE" \
  --arg slug "$SLUG" \
  --argjson tags "$TAG_JSON" \
  --argjson rca_warnings "$RCA_WARN_JSON" \
  --arg rca_quality "$RCA_QUALITY" \
  '{status:$status, type:$type, slug:$slug, tags:$tags, alerts:[], rca:{warnings:$rca_warnings, quality:$rca_quality}}'
