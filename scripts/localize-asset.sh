#!/usr/bin/env bash
# localize-asset.sh — 범용(generic) 자산을 프로젝트 맥락으로 구체화 (JSONL 기반)
#
# 사용법:
#   localize-asset.sh --slug "docker-build-cache-generic" [--base-dir .harnish]

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

ORIGINAL=$(jq -c --arg s "$SLUG" 'select(.slug == $s)' "$RAG_FILE" 2>/dev/null | head -1)

if [[ -z "$ORIGINAL" ]]; then
    echo "오류: slug '$SLUG' 없음" >&2
    exit 1
fi

# scope를 project로 변경한 사본 추가 (atomic write)
LOCALIZED=$(echo "$ORIGINAL" | jq -c '.scope = "project" | .slug = .slug + "-local" | .context = .context + " (로컬화)"')
TMPRAG=$(mktemp "${RAG_FILE}.XXXXXX")
trap 'rm -f "$TMPRAG"' EXIT
cp "$RAG_FILE" "$TMPRAG"
echo "$LOCALIZED" >> "$TMPRAG"
mv "$TMPRAG" "$RAG_FILE"

echo "{\"status\":\"localized\",\"slug\":\"$(echo "$ORIGINAL" | jq -r '.slug')-local\"}"
