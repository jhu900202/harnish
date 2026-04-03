#!/usr/bin/env bash
# skillify.sh — JSONL 자산에서 스킬 초안 생성
#
# 사용법:
#   skillify.sh --tag docker --skill-name docker-patterns [--base-dir .harnish]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE="$(resolve_base_dir)"
TAG="" SKILL_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)        TAG="$2"; shift 2;;
        --skill-name) SKILL_NAME="$2"; shift 2;;
        --base-dir)   BASE="$2"; shift 2;;
        *) shift;;
    esac
done

if [[ -z "$TAG" || -z "$SKILL_NAME" ]]; then
    echo "오류: --tag, --skill-name 필수" >&2
    exit 1
fi

RAG_FILE="$BASE/harnish-rag.jsonl"

if [[ ! -f "$RAG_FILE" ]]; then
    echo "오류: $RAG_FILE 없음" >&2
    exit 1
fi

# 해당 태그의 자산 수집
ASSETS=$(jq -c --arg t "$TAG" 'select(.tags[] == $t) | select(.compressed != true)' "$RAG_FILE" 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")
COUNT=$(echo "$ASSETS" | jq 'length')

if [[ "$COUNT" -eq 0 ]]; then
    echo "태그 '$TAG'에 해당하는 자산이 없습니다" >&2
    exit 1
fi

# 스킬 초안 생성
SKILL_DIR="skills/${SKILL_NAME}"
mkdir -p "$SKILL_DIR"

cat > "${SKILL_DIR}/SKILL.md" << EOF
---
name: ${SKILL_NAME}
version: 0.0.1
description: >
  ${TAG} 관련 축적 경험 기반 스킬 (${COUNT}건 자산에서 생성)
---

# ${SKILL_NAME}

> TODO: Claude가 아래 자산들을 분석하여 스킬 내용을 작성해야 합니다.

## 원본 자산 (${COUNT}건)

$(echo "$ASSETS" | jq -r '.[] | "- [\(.type)] \(.title): \(.body[0:80])"')
EOF

echo "{\"status\":\"generated\",\"skill_dir\":\"${SKILL_DIR}\",\"asset_count\":${COUNT}}"
