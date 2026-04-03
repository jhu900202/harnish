#!/usr/bin/env bash
# compress-assets.sh — 같은 태그 N건 이상 자산을 압축 (JSONL 기반)
#
# 사용법:
#   compress-assets.sh --tag api [--base-dir .harnish]
#   compress-assets.sh --all [--threshold 5]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE="$(resolve_base_dir)"
TAG="" ALL=false THRESHOLD=5

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)       TAG="$2"; shift 2;;
        --all)       ALL=true; shift;;
        --threshold) THRESHOLD="$2"; shift 2;;
        --base-dir)  BASE="$2"; shift 2;;
        *) shift;;
    esac
done

RAG_FILE="$BASE/harnish-rag.jsonl"

if [[ ! -f "$RAG_FILE" ]] || [[ ! -s "$RAG_FILE" ]]; then
    echo '{"status":"empty","compressed":0}'
    exit 0
fi

# 대상 태그 결정
if $ALL; then
    TAGS_OVER=$(jq -c 'select(.compressed != true) | .tags[]' "$RAG_FILE" 2>/dev/null \
        | sort | uniq -c | sort -rn \
        | awk -v t="$THRESHOLD" '$1 >= t {print $2}' | tr -d '"')
elif [[ -n "$TAG" ]]; then
    TAGS_OVER="$TAG"
else
    echo "오류: --tag 또는 --all 필수" >&2
    exit 1
fi

if [[ -z "$TAGS_OVER" ]]; then
    echo '{"status":"no_targets","compressed":0}'
    exit 0
fi

COMPRESSED=0
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE" "${TMPFILE}.new"' EXIT
cp "$RAG_FILE" "$TMPFILE"

while IFS= read -r target_tag; do
    [[ -z "$target_tag" ]] && continue

    COUNT=$(jq -c --arg t "$target_tag" 'select(.compressed != true) | select(.tags[] == $t)' "$TMPFILE" 2>/dev/null | wc -l | xargs)

    if [[ "$COUNT" -lt "$THRESHOLD" && "$ALL" == "true" ]]; then
        continue
    fi

    # 원본에 compressed:true 추가
    jq -c --arg t "$target_tag" 'if (.compressed != true) and (.tags | any(. == $t)) then . + {compressed: true} else . end' "$TMPFILE" > "${TMPFILE}.new"
    mv "${TMPFILE}.new" "$TMPFILE"

    # 요약본 1건 추가
    SUMMARY=$(jq -n -c \
        --arg type "pattern" \
        --arg slug "compressed-${target_tag}" \
        --arg title "[압축] ${target_tag} (${COUNT}건)" \
        --argjson tags "$(jq -n -c --arg t "$target_tag" '[$t]')" \
        --arg date "$(date +%Y-%m-%d)" \
        --arg scope "generic" \
        --arg body "TODO: Claude가 ${COUNT}건의 ${target_tag} 자산을 요약해야 합니다." \
        --arg context "compress-assets.sh" \
        --arg session "compress" \
        '{type:$type,slug:$slug,title:$title,tags:$tags,date:$date,scope:$scope,body:$body,context:$context,session:$session,compressed_summary:true}')

    echo "$SUMMARY" >> "$TMPFILE"
    ((COMPRESSED++)) || true
done <<< "$TAGS_OVER"

mv "$TMPFILE" "$RAG_FILE"
echo "{\"status\":\"compressed\",\"compressed\":${COMPRESSED}}"
