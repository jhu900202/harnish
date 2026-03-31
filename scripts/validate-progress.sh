#!/usr/bin/env bash
# validate-progress.sh — PROGRESS.md 구조 검증 스크립트
#
# 역할: PROGRESS.md가 harnish가 파싱할 수 있는 올바른 구조인지 검증한다.
#       세션 시작 시, 마일스톤 도달 시 자동 실행.
#
# 사용법:
#   bash validate-progress.sh [PROGRESS.md 경로]
#   bash validate-progress.sh                     # 현재 디렉토리의 PROGRESS.md
#
# 종료 코드:
#   0 — 구조 정상
#   1 — 구조 오류 발견 (상세 내용은 stderr)

set -euo pipefail

PROGRESS_FILE="${1:-PROGRESS.md}"

# ═══════════════════════════════════════
# 파일 존재 확인
# ═══════════════════════════════════════
if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "오류: PROGRESS.md 없음: $PROGRESS_FILE" >&2
    exit 1
fi

ERRORS=()
WARNINGS=()

# ═══════════════════════════════════════
# 필수 섹션 검증
# ═══════════════════════════════════════
# PROGRESS.md에 반드시 있어야 하는 섹션 헤더들
REQUIRED_SECTIONS=(
    "## 메타데이터"
    "## ✅ 완료 (Done)"
    "## 🔨 진행 중 (Doing)"
    "## 📋 예정 (Todo)"
)

for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -qF "$section" "$PROGRESS_FILE"; then
        ERRORS+=("필수 섹션 누락: '$section'")
    fi
done

# ═══════════════════════════════════════
# 메타데이터 필드 검증
# ═══════════════════════════════════════
# 메타데이터 섹션에서 필수 필드 확인
META_SECTION=$(sed -n '/^## 메타데이터/,/^## /p' "$PROGRESS_FILE" | head -n -1)

REQUIRED_META=("PRD" "시작" "마지막 세션" "현재 상태")
for field in "${REQUIRED_META[@]}"; do
    if ! echo "$META_SECTION" | grep -q "$field"; then
        ERRORS+=("메타데이터 필수 필드 누락: '$field'")
    fi
done

# ═══════════════════════════════════════
# 상태 이모지 검증
# ═══════════════════════════════════════
# 현재 상태에 유효한 이모지가 있는지 확인
# POSIX 호환: grep -oP 대신 grep -oE (macOS BSD grep은 -P 미지원)
STATUS_LINE=$(grep -oE '현재 상태.*' "$PROGRESS_FILE" | head -1 || echo "")
if [[ -n "$STATUS_LINE" ]]; then
    if ! echo "$STATUS_LINE" | grep -qE '(🟢|🟡|🔴|✅)'; then
        WARNINGS+=("현재 상태에 유효한 상태 이모지(🟢🟡🔴✅) 없음")
    fi
fi

# ═══════════════════════════════════════
# Doing 섹션 필수 필드 검증
# ═══════════════════════════════════════
# Doing 섹션에 태스크가 있다면 필수 필드를 확인
DOING_SECTION=$(sed -n '/^## 🔨 진행 중 (Doing)/,/^## /p' "$PROGRESS_FILE" | head -n -1)

# Doing에 Task가 있는지 확인
if echo "$DOING_SECTION" | grep -qE '### Task'; then
    DOING_REQUIRED=("시작" "현재" "마지막 액션" "다음 액션")
    for field in "${DOING_REQUIRED[@]}"; do
        if ! echo "$DOING_SECTION" | grep -q "$field"; then
            WARNINGS+=("진행 중 태스크에 '$field' 필드 누락 — 세션 복원 정확도 저하")
        fi
    done
fi

# ═══════════════════════════════════════
# Done 섹션 구조 검증
# ═══════════════════════════════════════
DONE_SECTION=$(sed -n '/^## ✅ 완료 (Done)/,/^## /p' "$PROGRESS_FILE" | head -n -1)

# 완료된 태스크가 있다면 필수 필드 확인
# grep -c exits 1 when no match — use || true to prevent pipefail abort
DONE_TASKS=$(echo "$DONE_SECTION" | grep -c '\[x\]') || true
if [[ "$DONE_TASKS" -gt 0 ]]; then
    # 최소한 '결과' 필드가 있어야 함
    DONE_RESULTS=$(echo "$DONE_SECTION" | grep -c '결과') || true
    if [[ "$DONE_RESULTS" -eq 0 ]]; then
        WARNINGS+=("완료된 태스크에 '결과' 필드 없음")
    fi
fi

# ═══════════════════════════════════════
# 선택 섹션 검증
# ═══════════════════════════════════════
OPTIONAL_SECTIONS=(
    "## ⚠️ 이슈 · 결정 로그"
    "## 🔴 금지사항 위반 기록"
    "## 📊 요약 통계"
)

for section in "${OPTIONAL_SECTIONS[@]}"; do
    if ! grep -qF "$section" "$PROGRESS_FILE"; then
        WARNINGS+=("선택 섹션 누락: '$section' — 있으면 추적이 용이")
    fi
done

# ═══════════════════════════════════════
# 결과 출력
# ═══════════════════════════════════════
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "❌ PROGRESS.md 구조 오류 발견:" >&2
    for err in "${ERRORS[@]}"; do
        echo "  • $err" >&2
    done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "⚠️ 경고:" >&2
    for warn in "${WARNINGS[@]}"; do
        echo "  • $warn" >&2
    done
fi

if [[ ${#ERRORS[@]} -eq 0 ]]; then
    echo "✅ PROGRESS.md 구조 정상 (경고 ${#WARNINGS[@]}건)"
    exit 0
else
    echo "❌ 구조 오류 ${#ERRORS[@]}건, 경고 ${#WARNINGS[@]}건" >&2
    exit 1
fi
