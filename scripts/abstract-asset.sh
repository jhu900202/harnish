#!/usr/bin/env bash
# abstract-asset.sh — 프로젝트 특정 자산을 범용(generic)으로 추상화 (JSONL 기반)
#
# 사용법:
#   abstract-asset.sh --slug "docker-build-cache" [--base-dir .harnish]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE="$(resolve_base_dir)"
SLUG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --slug)     SLUG="$2"; shift 2;;
        --base-dir) BASE="$2"; shift 2;;
        *) shift;;
    esac
done

if [[ -z "$SLUG" ]]; then
    echo "오류: --slug 필수" >&2
    exit 1
fi

RAG_FILE="$BASE/harnish-rag.jsonl"

if [[ ! -f "$RAG_FILE" ]]; then
    echo "오류: $RAG_FILE 없음" >&2
    exit 1
fi

# 원본 찾기
ORIGINAL=$(jq -c --arg s "$SLUG" 'select(.slug == $s)' "$RAG_FILE" 2>/dev/null | head -1)

if [[ -z "$ORIGINAL" ]]; then
    echo "오류: slug '$SLUG' 없음" >&2
    exit 1
fi

# scope를 generic으로 변경한 사본 추가 (atomic write)
ABSTRACTED=$(echo "$ORIGINAL" | jq -c '.scope = "generic" | .slug = .slug + "-generic" | .context = .context + " (추상화)"')
TMPRAG=$(mktemp "${RAG_FILE}.XXXXXX")
trap 'rm -f "$TMPRAG"' EXIT
cp "$RAG_FILE" "$TMPRAG"
echo "$ABSTRACTED" >> "$TMPRAG"
mv "$TMPRAG" "$RAG_FILE"

echo "{\"status\":\"abstracted\",\"slug\":\"${SLUG}-generic\"}"
