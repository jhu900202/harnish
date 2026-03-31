#!/usr/bin/env bash
# check-violations.sh — 금지사항 위반 여부를 PROGRESS.md에서 확인
# 사용법: bash check-violations.sh [PROGRESS.md 경로]

set -euo pipefail

PROGRESS_FILE="${1:-./PROGRESS.md}"

if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "ERROR: $PROGRESS_FILE not found" >&2
  exit 1
fi

# grep -c returns exit 1 when no match → use || true to prevent double output
VIOLATIONS=$(grep -c '🔴 위반:' "$PROGRESS_FILE" || true)
ESCALATIONS=$(grep -c '🆘 에스컬레이션' "$PROGRESS_FILE" || true)

echo "위반 기록: ${VIOLATIONS}건"
echo "에스컬레이션: ${ESCALATIONS}건"

if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo ""
  echo "── 위반 내역 ──"
  grep -A 3 '🔴 위반:' "$PROGRESS_FILE" || true
fi

if [[ "$ESCALATIONS" -gt 0 ]]; then
  echo ""
  echo "── 에스컬레이션 내역 ──"
  grep -A 5 '🆘 에스컬레이션' "$PROGRESS_FILE" || true
fi
