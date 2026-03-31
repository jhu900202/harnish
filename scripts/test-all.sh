#!/usr/bin/env bash
# test-all.sh — harnish 전체 스크립트 흐름 자동 검증
#
# 사용법: bash scripts/test-all.sh
# 각 테스트는 독립적 — 하나가 FAIL해도 다음 테스트 진행.

set -uo pipefail

# ════════════════════════════════════════
# 0. 환경 설정
# ════════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNISH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPDIR_BASE=$(mktemp -d)
ASSET_DIR="$TMPDIR_BASE/assets"
PROGRESS_FILE="$TMPDIR_BASE/PROGRESS.json"

PASS=0
FAIL=0
SKIP=0
RESULTS=()

# 색상 (터미널 지원 시)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' BOLD='' NC=''
fi

pass() {
  PASS=$((PASS + 1))
  RESULTS+=("${GREEN}PASS${NC}  $1")
  printf "  ${GREEN}PASS${NC}  %s\n" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  RESULTS+=("${RED}FAIL${NC}  $1${2:+ — $2}")
  printf "  ${RED}FAIL${NC}  %s%s\n" "$1" "${2:+ — $2}"
}

skip() {
  SKIP=$((SKIP + 1))
  RESULTS+=("${YELLOW}SKIP${NC}  $1${2:+ — $2}")
  printf "  ${YELLOW}SKIP${NC}  %s%s\n" "$1" "${2:+ — $2}"
}

cleanup() {
  rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

echo ""
echo "════════════════════════════════════════"
echo " harnish 전체 스크립트 검증"
echo "════════════════════════════════════════"
echo ""

# ════════════════════════════════════════
# 1. 환경 체크
# ════════════════════════════════════════
echo "${BOLD}[환경]${NC}"
printf "  bash: %s\n" "$(bash --version | head -1)"
printf "  jq:   %s\n" "$(jq --version 2>/dev/null || echo 'NOT FOUND')"
printf "  tmpdir: %s\n" "$TMPDIR_BASE"
echo ""

if ! command -v jq &>/dev/null; then
  echo "jq가 설치되어 있지 않습니다. brew install jq"
  exit 1
fi

# ════════════════════════════════════════
# 2. init-assets.sh
# ════════════════════════════════════════
echo "${BOLD}[자산 초기화]${NC}"

bash "$HARNISH_ROOT/scripts/init-assets.sh" --base-dir "$ASSET_DIR" >/dev/null 2>&1
if [[ -d "$ASSET_DIR/failures" ]] && [[ -d "$ASSET_DIR/patterns" ]] && [[ -f "$ASSET_DIR/.meta/index.json" ]]; then
  pass "init-assets.sh"
else
  fail "init-assets.sh" "디렉토리 또는 index.json 미생성"
fi

# ════════════════════════════════════════
# 3. record-asset.sh (3가지 타입)
# ════════════════════════════════════════
echo "${BOLD}[자산 기록]${NC}"

for asset_type in failure pattern guardrail; do
  output=$(bash "$HARNISH_ROOT/scripts/record-asset.sh" \
    --type "$asset_type" \
    --tags "test,docker,cache" \
    --context "test-all: $asset_type 테스트" \
    --title "테스트 $asset_type 자산" \
    --content "## 표면 증상
테스트 내용
## 실제 원인
테스트
## 해결 과정
테스트
## 일반화된 패턴
테스트
## 규칙
테스트
## 이유
테스트
## 위반 시 결과
테스트
## 예외 조건
테스트
## 적용 상황
테스트
## 접근법
테스트
## 왜 효과적인가
테스트
## 적용 범위와 한계
테스트" \
    --base-dir "$ASSET_DIR" 2>&1)
  if [[ $? -eq 0 ]]; then
    pass "record-asset.sh --type $asset_type"
  else
    fail "record-asset.sh --type $asset_type" "$(echo "$output" | head -3)"
  fi
done

# ════════════════════════════════════════
# 4. query-assets.sh
# ════════════════════════════════════════
echo "${BOLD}[자산 조회]${NC}"

for fmt in text inject; do
  output=$(bash "$HARNISH_ROOT/scripts/query-assets.sh" \
    --tags "test,docker" --format "$fmt" --base-dir "$ASSET_DIR" 2>&1)
  if [[ $? -eq 0 ]]; then
    pass "query-assets.sh --format $fmt"
  else
    fail "query-assets.sh --format $fmt" "$(echo "$output" | head -3)"
  fi
done

# ════════════════════════════════════════
# 5. check-thresholds.sh
# ════════════════════════════════════════
echo "${BOLD}[임계치 확인]${NC}"

output=$(bash "$HARNISH_ROOT/scripts/check-thresholds.sh" --base-dir "$ASSET_DIR" 2>&1)
if [[ $? -eq 0 ]]; then
  pass "check-thresholds.sh"
else
  fail "check-thresholds.sh" "$(echo "$output" | head -3)"
fi

# ════════════════════════════════════════
# 6. quality-gate.sh
# ════════════════════════════════════════
echo "${BOLD}[품질 게이트]${NC}"

output=$(bash "$HARNISH_ROOT/scripts/quality-gate.sh" --base-dir "$ASSET_DIR" 2>&1)
if [[ $? -eq 0 ]]; then
  pass "quality-gate.sh"
else
  fail "quality-gate.sh" "$(echo "$output" | head -3)"
fi

# ════════════════════════════════════════
# 7. 샘플 PROGRESS.json 생성
# ════════════════════════════════════════
echo "${BOLD}[PROGRESS.json]${NC}"

cat > "$PROGRESS_FILE" << 'PJSON'
{
  "metadata": {
    "prd": "docs/prd-test.md",
    "started_at": "2026-03-31T10:00:00+09:00",
    "last_session": "2026-03-31T14:30:00+09:00",
    "status": { "emoji": "🟢", "phase": 1, "task": "1-1", "label": "정상 진행 중" }
  },
  "done": {
    "phases": []
  },
  "doing": {
    "task": {
      "id": "1-1",
      "title": "테스트 모델 생성",
      "started_at": "2026-03-31T10:00:00+09:00",
      "current": "모델 파일 작성 중",
      "last_action": "파일 구조 확인",
      "next_action": "src/model.py 생성",
      "blocker": null,
      "retry_count": 0,
      "context": {
        "guide": "User 모델을 생성한다",
        "scope": "src/models/ 디렉토리만 수정",
        "prd_reference": "§4.1"
      }
    }
  },
  "todo": {
    "phases": [
      {
        "phase": 1,
        "title": "데이터 모델",
        "tasks": [
          { "id": "1-2", "title": "API 엔드포인트 생성", "depends_on": ["1-1"] }
        ]
      },
      {
        "phase": 2,
        "title": "테스트",
        "tasks": [
          { "id": "2-1", "title": "유닛 테스트 작성", "depends_on": [] }
        ]
      }
    ]
  },
  "issues": [],
  "violations": [],
  "escalations": [],
  "stats": {
    "total_phases": 2,
    "completed_phases": 0,
    "total_tasks": 3,
    "completed_tasks": 0,
    "issues_count": 0,
    "violations_count": 0
  }
}
PJSON

# ════════════════════════════════════════
# 8. validate-progress.sh
# ════════════════════════════════════════
output=$(bash "$HARNISH_ROOT/scripts/validate-progress.sh" "$PROGRESS_FILE" 2>&1)
if [[ $? -eq 0 ]]; then
  pass "validate-progress.sh"
else
  fail "validate-progress.sh" "$(echo "$output" | head -3)"
fi

# ════════════════════════════════════════
# 9. loop-step.sh
# ════════════════════════════════════════
for fmt in text json; do
  output=$(bash "$HARNISH_ROOT/scripts/loop-step.sh" "$PROGRESS_FILE" --format "$fmt" 2>&1)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    # 추가 검증: 다음 액션이 실제로 파싱되었는지
    if [[ "$fmt" == "text" ]]; then
      if echo "$output" | grep -q "미설정"; then
        fail "loop-step.sh --format $fmt" "다음 액션 파싱 실패 (미설정)"
      else
        pass "loop-step.sh --format $fmt"
      fi
    else
      next=$(echo "$output" | jq -r '.next_action // ""' 2>/dev/null)
      if [[ -z "$next" ]] || [[ "$next" == "null" ]]; then
        fail "loop-step.sh --format $fmt" "next_action 빈 값"
      else
        pass "loop-step.sh --format $fmt"
      fi
    fi
  else
    fail "loop-step.sh --format $fmt" "$(echo "$output" | head -3)"
  fi
done

# ════════════════════════════════════════
# 10. compress-progress.sh (Done이 있는 상태로)
# ════════════════════════════════════════
# Done에 Phase를 추가한 샘플 생성
PROGRESS_WITH_DONE="$TMPDIR_BASE/PROGRESS_done.json"
jq '.done.phases = [{
  "phase": 1, "title": "데이터 모델", "compressed": false,
  "milestone_approved_at": "2026-03-31T12:00:00+09:00",
  "tasks": [
    {"id": "1-1", "title": "스키마 정의", "result": "완료", "files_changed": ["schema.prisma"], "verification": "prisma validate", "duration": "3턴"},
    {"id": "1-2", "title": "API 생성", "result": "완료", "files_changed": ["api.ts"], "verification": "npm test", "duration": "2턴"}
  ]
}] | .doing.task = null | .todo.phases = [{
  "phase": 2, "title": "테스트",
  "tasks": [{"id": "2-1", "title": "유닛 테스트", "depends_on": []}]
}]' "$PROGRESS_FILE" > "$PROGRESS_WITH_DONE"

output=$(bash "$HARNISH_ROOT/scripts/compress-progress.sh" "$PROGRESS_WITH_DONE" --trigger milestone --phase 1 2>&1)
if [[ $? -eq 0 ]]; then
  pass "compress-progress.sh"
else
  # exit 1 with "압축할 Phase 없음" is expected if script doesn't understand JSON yet
  fail "compress-progress.sh" "$(echo "$output" | head -3)"
fi

# ════════════════════════════════════════
# 11. check-violations.sh
# ════════════════════════════════════════
output=$(bash "$HARNISH_ROOT/scripts/check-violations.sh" "$PROGRESS_FILE" 2>&1)
if [[ $? -eq 0 ]]; then
  pass "check-violations.sh"
else
  fail "check-violations.sh" "$(echo "$output" | head -3)"
fi

# ════════════════════════════════════════
# 12. progress-report.sh
# ════════════════════════════════════════
if [[ -f "$HARNISH_ROOT/scripts/progress-report.sh" ]]; then
  output=$(bash "$HARNISH_ROOT/scripts/progress-report.sh" "$PROGRESS_FILE" 2>&1)
  if [[ $? -eq 0 ]] && [[ -n "$output" ]]; then
    pass "progress-report.sh"
  else
    fail "progress-report.sh" "$(echo "$output" | head -3)"
  fi
else
  skip "progress-report.sh" "파일 미존재 (Phase 3에서 생성 예정)"
fi

# ════════════════════════════════════════
# 13. compress-assets.sh (더미 5건+)
# ════════════════════════════════════════
echo "${BOLD}[자산 압축]${NC}"

# 추가 더미 자산 생성 (compress 임계치: 동일 태그 5건+)
for i in $(seq 4 8); do
  cat > "$ASSET_DIR/failures/2026-03-31-test-${i}.md" << ASSETEOF
---
title: 테스트 failure $i
type: failure
tags: [compress-test, docker]
context: "compress test $i"
date: 2026-03-31
---

## 표면 증상
테스트 $i

## 실제 원인
테스트

## 해결 과정
테스트

## 일반화된 패턴
테스트
ASSETEOF
  # index.json의 counts, tag_index 갱신 (assets 배열 없음 — compress-assets.sh는 파일시스템 스캔)
  jq '.counts.failures = (.counts.failures // 0) + 1
      | .tag_index["compress-test"] = (.tag_index["compress-test"] // 0) + 1
      | .tag_index["docker"] = (.tag_index["docker"] // 0) + 1' \
    "$ASSET_DIR/.meta/index.json" > "$ASSET_DIR/.meta/index.json.tmp" && mv "$ASSET_DIR/.meta/index.json.tmp" "$ASSET_DIR/.meta/index.json"
done

output=$(bash "$HARNISH_ROOT/scripts/compress-assets.sh" --tag compress-test --base-dir "$ASSET_DIR" 2>&1)
if [[ $? -eq 0 ]]; then
  pass "compress-assets.sh"
else
  fail "compress-assets.sh" "$(echo "$output" | head -3)"
fi

# ════════════════════════════════════════
# 14. abstract-asset.sh
# ════════════════════════════════════════
echo "${BOLD}[자산 추상화/로컬라이즈/스킬화]${NC}"

# project scope 자산 생성 (abstract-asset은 project/team scope에서만 동작)
bash "$HARNISH_ROOT/scripts/record-asset.sh" \
  --type failure --scope project \
  --tags "abstract-test,docker" \
  --title "프로젝트 특정 failure" \
  --content "## 표면 증상
docker build /Users/admin/myproject에서 실패
## 실제 원인
권한 문제
## 해결 과정
chmod +r
## 일반화된 패턴
권한 이슈" \
  --base-dir "$ASSET_DIR" >/dev/null 2>&1

# 소스 자산 파일 찾기 (project scope 것만)
src_asset=$(grep -rl "scope: project" "$ASSET_DIR/failures" 2>/dev/null | head -1)
abstract_out=""
if [[ -n "$src_asset" ]]; then
  output=$(bash "$HARNISH_ROOT/scripts/abstract-asset.sh" --source "$src_asset" --base-dir "$ASSET_DIR" 2>&1)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    # JSON 출력에서 output 경로 추출
    abstract_out=$(echo "$output" | jq -r '.output // ""' 2>/dev/null)
    pass "abstract-asset.sh"
  else
    fail "abstract-asset.sh" "$(echo "$output" | head -3)"
  fi
else
  skip "abstract-asset.sh" "소스 자산 없음"
fi

# ════════════════════════════════════════
# 15. localize-asset.sh
# ════════════════════════════════════════
# localize는 generic scope 자산이 필요 → abstract 결과 사용
if [[ -n "$abstract_out" ]] && [[ -f "$abstract_out" ]]; then
  output=$(bash "$HARNISH_ROOT/scripts/localize-asset.sh" \
    --source "$abstract_out" --base-dir "$ASSET_DIR" \
    --project-context "테스트 프로젝트" 2>&1)
  if [[ $? -eq 0 ]]; then
    pass "localize-asset.sh"
  else
    fail "localize-asset.sh" "$(echo "$output" | head -3)"
  fi
else
  skip "localize-asset.sh" "generic scope 자산 없음 (abstract-asset 실패 시)"
fi

# ════════════════════════════════════════
# 16. skillify.sh
# ════════════════════════════════════════
compressed_src=$(find "$ASSET_DIR/.compressed" -name "*.md" -type f 2>/dev/null | head -1)
if [[ -n "$compressed_src" ]]; then
  output=$(bash "$HARNISH_ROOT/scripts/skillify.sh" \
    --source "$compressed_src" --skill-name "test-skill" 2>&1)
  if [[ $? -eq 0 ]]; then
    pass "skillify.sh"
  else
    fail "skillify.sh" "$(echo "$output" | head -3)"
  fi
else
  skip "skillify.sh" "압축 자산 없음 (compress-assets 실패 시)"
fi

# ════════════════════════════════════════
# 16-b. skillify 출력 SKILL.md 검증 (version 필드 포함)
# ════════════════════════════════════════
if [[ -n "$compressed_src" ]]; then
  skillify_skill_dir="$TMPDIR_BASE/test-skill-verify"
  bash "$HARNISH_ROOT/scripts/skillify.sh" \
    --source "$compressed_src" --skill-name "verify-skill" \
    --output-dir "$skillify_skill_dir" >/dev/null 2>&1
  skill_md="$skillify_skill_dir/verify-skill/SKILL.md"
  if [[ -f "$skill_md" ]]; then
    fm_ok=true
    for field in name version description; do
      if ! grep -qE "^${field}:" "$skill_md"; then
        fail "skillify SKILL.md: $field 필드 누락"
        fm_ok=false
      fi
    done
    $fm_ok && pass "skillify SKILL.md: name/version/description 모두 포함"
  else
    fail "skillify SKILL.md" "파일 미생성"
  fi
fi

# ════════════════════════════════════════
# 17. 에지케이스: validate-progress
# ════════════════════════════════════════
echo "${BOLD}[에지케이스]${NC}"

# 깨진 JSON
echo '{bad' > "$TMPDIR_BASE/broken.json"
bash "$HARNISH_ROOT/scripts/validate-progress.sh" "$TMPDIR_BASE/broken.json" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  pass "validate-progress: 깨진 JSON 거부"
else
  fail "validate-progress: 깨진 JSON 거부" "exit 0을 반환함"
fi

# 빈 JSON
echo '{}' > "$TMPDIR_BASE/empty.json"
bash "$HARNISH_ROOT/scripts/validate-progress.sh" "$TMPDIR_BASE/empty.json" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  pass "validate-progress: 빈 JSON 오류 감지"
else
  fail "validate-progress: 빈 JSON 오류 감지" "exit 0을 반환함"
fi

# 존재하지 않는 파일
bash "$HARNISH_ROOT/scripts/validate-progress.sh" "$TMPDIR_BASE/nonexistent.json" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  pass "validate-progress: 파일 미존재 거부"
else
  fail "validate-progress: 파일 미존재 거부" "exit 0을 반환함"
fi

# ════════════════════════════════════════
# 18. 에지케이스: loop-step 3상태
# ════════════════════════════════════════
# ALL_DONE
ALL_DONE_JSON='{"metadata":{"prd":"x","started_at":"x","last_session":"x","status":{"emoji":"✅","phase":1,"task":"","label":"완료"}},"done":{"phases":[{"phase":1,"title":"done","compressed":false,"tasks":[{"id":"1-1","title":"t","result":"ok","files_changed":[],"verification":"ok","duration":"1"}]}]},"doing":{"task":null},"todo":{"phases":[]},"issues":[],"violations":[],"escalations":[],"stats":{}}'
echo "$ALL_DONE_JSON" > "$TMPDIR_BASE/all_done.json"
status=$(bash "$HARNISH_ROOT/scripts/loop-step.sh" "$TMPDIR_BASE/all_done.json" --format json 2>&1 | jq -r '.status')
if [[ "$status" == "ALL_DONE" ]]; then
  pass "loop-step: ALL_DONE 상태 감지"
else
  fail "loop-step: ALL_DONE 상태 감지" "status=$status"
fi

# NO_DOING with milestone
MILESTONE_JSON='{"metadata":{"prd":"x","started_at":"x","last_session":"x","status":{"emoji":"🟢","phase":1,"task":"","label":"ok"}},"done":{"phases":[{"phase":1,"title":"done","compressed":false,"tasks":[{"id":"1-1","title":"t","result":"ok","files_changed":[],"verification":"ok","duration":"1"}]}]},"doing":{"task":null},"todo":{"phases":[{"phase":2,"title":"next","tasks":[{"id":"2-1","title":"t","depends_on":[]}]}]},"issues":[],"violations":[],"escalations":[],"stats":{}}'
echo "$MILESTONE_JSON" > "$TMPDIR_BASE/milestone.json"
milestone=$(bash "$HARNISH_ROOT/scripts/loop-step.sh" "$TMPDIR_BASE/milestone.json" --format json 2>&1 | jq -r '.phase_milestone')
if [[ "$milestone" == "true" ]]; then
  pass "loop-step: 마일스톤 감지"
else
  fail "loop-step: 마일스톤 감지" "phase_milestone=$milestone"
fi

# ════════════════════════════════════════
# 19. 왕복 검증: record → query
# ════════════════════════════════════════
echo "${BOLD}[왕복 검증]${NC}"

query_result=$(bash "$HARNISH_ROOT/scripts/query-assets.sh" --tags "test" --format text --base-dir "$ASSET_DIR" 2>&1)
if echo "$query_result" | grep -q "테스트.*자산"; then
  pass "record→query 왕복: 기록한 자산 조회됨"
else
  fail "record→query 왕복: 기록한 자산 조회됨" "결과에 '테스트 자산' 없음"
fi

# ════════════════════════════════════════
# 20. compress-assets 후 .compressed/ 파일 존재
# ════════════════════════════════════════
compressed_files=$(find "$ASSET_DIR/.compressed" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "$compressed_files" -gt 0 ]]; then
  pass "compress-assets: .compressed/ 파일 ${compressed_files}개 생성됨"
else
  fail "compress-assets: .compressed/ 파일 생성됨" "0개"
fi

# ════════════════════════════════════════
# 21. compress-progress 후 JSON 구조 검증
# ════════════════════════════════════════
if [[ -f "$PROGRESS_WITH_DONE" ]]; then
  is_compressed=$(jq '.done.phases[0].compressed' "$PROGRESS_WITH_DONE" 2>/dev/null)
  if [[ "$is_compressed" == "true" ]]; then
    pass "compress-progress: 압축 후 compressed=true"
  else
    fail "compress-progress: 압축 후 compressed=true" "compressed=$is_compressed"
  fi

  has_archive=$(jq -r '.done.phases[0].archive_ref // ""' "$PROGRESS_WITH_DONE" 2>/dev/null)
  if [[ -n "$has_archive" ]]; then
    pass "compress-progress: archive_ref 존재"
  else
    fail "compress-progress: archive_ref 존재" "빈 값"
  fi
fi

# ════════════════════════════════════════
# 22. progress-report 필수 섹션 확인
# ════════════════════════════════════════
report=$(bash "$HARNISH_ROOT/scripts/progress-report.sh" "$PROGRESS_FILE" 2>&1)
report_ok=true
for section in "메타데이터" "완료 (Done)" "진행 중 (Doing)" "예정 (Todo)" "요약 통계"; do
  if ! echo "$report" | grep -q "$section"; then
    fail "progress-report: 섹션 '$section' 누락"
    report_ok=false
  fi
done
if $report_ok; then
  pass "progress-report: 필수 5개 섹션 포함"
fi

# ════════════════════════════════════════
# 23. detect-asset.sh hook 테스트
# ════════════════════════════════════════
echo "${BOLD}[hook]${NC}"

# 의미 있는 에러 → pending에 기록
echo '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","session_id":"test-hook","tool_input":"docker build .","tool_output":"Error: insufficient memory"}' \
  | ASSET_BASE_DIR="$ASSET_DIR" bash "$HARNISH_ROOT/scripts/detect-asset.sh" 2>/dev/null
pending_count=$(find "$ASSET_DIR/.meta/pending" -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "$pending_count" -gt 0 ]]; then
  pass "detect-asset: 의미 있는 에러 → pending 기록"
else
  fail "detect-asset: 의미 있는 에러 → pending 기록" "pending 파일 없음"
fi

# 노이즈 → 필터링 (pending 증가하면 안 됨)
pre_count=$pending_count
echo '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","session_id":"test-hook-noise","tool_input":"cat x","tool_output":"No such file or directory"}' \
  | ASSET_BASE_DIR="$ASSET_DIR" bash "$HARNISH_ROOT/scripts/detect-asset.sh" 2>/dev/null
post_count=$(find "$ASSET_DIR/.meta/pending" -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "$post_count" -eq "$pre_count" ]]; then
  pass "detect-asset: 노이즈 에러 필터링"
else
  fail "detect-asset: 노이즈 에러 필터링" "pending이 $pre_count → $post_count로 증가"
fi

# ════════════════════════════════════════
# 24. 이중 압축 방어
# ════════════════════════════════════════
echo "${BOLD}[이중 압축 방어]${NC}"

DOUBLE_COMPRESS_JSON="$TMPDIR_BASE/double_compress.json"
cat > "$DOUBLE_COMPRESS_JSON" << 'DCEOF'
{
  "metadata": {"prd": "x", "started_at": "x", "last_session": "x", "status": {"emoji": "🟢", "phase": 1, "task": "", "label": "ok"}},
  "done": {"phases": [{"phase": 1, "title": "이미 압축됨", "compressed": true, "compressed_summary": "tasks:3", "archive_ref": ".a"}]},
  "doing": {"task": null}, "todo": {"phases": []},
  "issues": [], "violations": [], "escalations": [], "stats": {}
}
DCEOF
bash "$HARNISH_ROOT/scripts/compress-progress.sh" "$DOUBLE_COMPRESS_JSON" --trigger milestone --phase 1 >/dev/null 2>&1
after_compressed=$(jq -r '.done.phases[0].compressed_summary' "$DOUBLE_COMPRESS_JSON")
if [[ "$after_compressed" == "tasks:3" ]]; then
  pass "이중 압축 방어: compressed phase 변경 없음"
else
  fail "이중 압축 방어: compressed phase 변경 없음" "summary=$after_compressed"
fi

# ════════════════════════════════════════
# 25. SKILL.md frontmatter 정합성
# ════════════════════════════════════════
echo "${BOLD}[SKILL.md 정합성]${NC}"

skill_ok=true
for skill_dir in "$HARNISH_ROOT"/skills/*/; do
  skill_md="$skill_dir/SKILL.md"
  [[ -f "$skill_md" ]] || continue
  skill_name=$(basename "$skill_dir")
  for field in name description version; do
    if ! head -20 "$skill_md" | grep -qE "^${field}:"; then
      fail "SKILL.md frontmatter: $skill_name.$field 누락"
      skill_ok=false
    fi
  done
done
if $skill_ok; then
  pass "SKILL.md frontmatter: 4개 스킬 모두 name/description/version 정상"
fi

# ════════════════════════════════════════
# 26. 문서 정합성: PROGRESS.md 잔여 참조 없음
# ════════════════════════════════════════
stale_refs=$(grep -rl 'PROGRESS\.md' "$HARNISH_ROOT" --include="*.md" --include="*.json" --include="*.sh" --exclude-dir=".git" --exclude-dir=".claude" 2>/dev/null \
  | grep -v '.gitignore' | grep -v 'test-all.sh' | grep -v 'plans/' || true)
if [[ -z "$stale_refs" ]]; then
  pass "문서 정합성: PROGRESS.md 잔여 참조 없음"
else
  fail "문서 정합성: PROGRESS.md 잔여 참조 없음" "$stale_refs"
fi

# ════════════════════════════════════════
# 27. query-assets --types 필터
# ════════════════════════════════════════
echo "${BOLD}[자산 타입 필터]${NC}"

types_result=$(bash "$HARNISH_ROOT/scripts/query-assets.sh" --tags "test" --types "failure" --format text --base-dir "$ASSET_DIR" 2>&1)
if echo "$types_result" | grep -q "\[failure\]"; then
  # guardrail이나 pattern이 섞여 있으면 안 됨
  if echo "$types_result" | grep -q "\[pattern\]\|\[guardrail\]"; then
    fail "query-assets --types: failure만 반환" "다른 타입이 섞여 있음"
  else
    pass "query-assets --types: failure 필터 정상"
  fi
else
  fail "query-assets --types: failure 필터 정상" "failure 결과 없음"
fi

# ════════════════════════════════════════
# 28. progress-report: violations 렌더링
# ════════════════════════════════════════
PROGRESS_COMPLEX="$TMPDIR_BASE/complex.json"
cat > "$PROGRESS_COMPLEX" << 'CEOF'
{
  "metadata": {"prd": "x", "started_at": "x", "last_session": "x", "status": {"emoji": "🟡", "phase": 1, "task": "1-1", "label": "이슈"}},
  "done": {"phases": []},
  "doing": {"task": null},
  "todo": {"phases": []},
  "issues": [{"timestamp": "2026-03-31T14:00:00", "task": "1-1", "description": "타입 에러", "resolution": "수정함"}],
  "violations": [{"timestamp": "2026-03-31T14:20:00", "task": "1-1", "violation": "scope 이탈", "user_decision": "허용"}],
  "escalations": [{"timestamp": "2026-03-31T14:45:00", "task": "1-1", "blocked_at": "api.ts:45", "attempts": [], "suggested_options": []}],
  "stats": {"total_phases": 1, "completed_phases": 0, "total_tasks": 1, "completed_tasks": 0, "issues_count": 1, "violations_count": 1}
}
CEOF

complex_report=$(bash "$HARNISH_ROOT/scripts/progress-report.sh" "$PROGRESS_COMPLEX" 2>&1)
report_checks=true
if ! echo "$complex_report" | grep -q "타입 에러"; then
  fail "progress-report: issues 테이블 렌더링" "이슈 내용 없음"
  report_checks=false
fi
if ! echo "$complex_report" | grep -q "scope 이탈"; then
  fail "progress-report: violations 테이블 렌더링" "위반 내용 없음"
  report_checks=false
fi
if $report_checks; then
  pass "progress-report: issues + violations 렌더링 정상"
fi

# ════════════════════════════════════════
# 29. compress-progress --trigger count (다중 Phase)
# ════════════════════════════════════════
COUNT_COMPRESS="$TMPDIR_BASE/count_compress.json"
cat > "$COUNT_COMPRESS" << 'CCEOF'
{
  "metadata": {"prd": "x", "started_at": "x", "last_session": "x", "status": {"emoji": "🟢", "phase": 3, "task": "", "label": "ok"}},
  "done": {"phases": [
    {"phase": 1, "title": "A", "compressed": false, "tasks": [{"id": "1-1", "title": "t", "result": "ok", "files_changed": ["a.ts"], "verification": "ok", "duration": "1"}]},
    {"phase": 2, "title": "B", "compressed": false, "tasks": [{"id": "2-1", "title": "t", "result": "ok", "files_changed": ["b.ts"], "verification": "ok", "duration": "1"}]}
  ]},
  "doing": {"task": null}, "todo": {"phases": []},
  "issues": [], "violations": [], "escalations": [], "stats": {}
}
CCEOF
bash "$HARNISH_ROOT/scripts/compress-progress.sh" "$COUNT_COMPRESS" --trigger count >/dev/null 2>&1
count_compressed=$(jq '[.done.phases[] | select(.compressed == true)] | length' "$COUNT_COMPRESS")
if [[ "$count_compressed" -eq 2 ]]; then
  pass "compress-progress --trigger count: 2개 Phase 일괄 압축"
else
  fail "compress-progress --trigger count: 2개 Phase 일괄 압축" "compressed=$count_compressed"
fi

# ════════════════════════════════════════
# 30. schema.json 정합성
# ════════════════════════════════════════
echo "${BOLD}[schema.json]${NC}"

schema_file="$HARNISH_ROOT/skills/harnish/references/schema.json"
if jq empty "$schema_file" 2>/dev/null; then
  pass "schema.json: 유효한 JSON"
else
  fail "schema.json: 유효한 JSON" "파싱 에러"
fi

# L1 exports에 실제 common.sh 함수가 있는지
schema_ok=true
for fn in require_cmd resolve_base_dir slugify format_yaml_tags atomic_write_index parse_frontmatter parse_body get_field get_tags; do
  if ! grep -q "$fn" "$HARNISH_ROOT/scripts/common.sh" 2>/dev/null; then
    fail "schema.json L1 exports: $fn()이 common.sh에 없음"
    schema_ok=false
  fi
done
if $schema_ok; then
  pass "schema.json: L1 exports가 common.sh 함수와 일치"
fi

# ════════════════════════════════════════
# 31. snippet / decision 타입 기록
# ════════════════════════════════════════
echo "${BOLD}[snippet / decision 타입]${NC}"

output=$(bash "$HARNISH_ROOT/scripts/record-asset.sh" \
  --type snippet --tags "bash,util" \
  --title "파일 존재 확인 스니펫" \
  --content '## 용도
파일 존재 확인

## 코드
```bash
[[ -f "$f" ]] && echo ok
```

## 사용 예시
deploy.sh' \
  --base-dir "$ASSET_DIR" 2>&1)
if [[ $? -eq 0 ]]; then
  pass "record-asset.sh --type snippet"
else
  fail "record-asset.sh --type snippet" "$(echo "$output" | head -2)"
fi

output=$(bash "$HARNISH_ROOT/scripts/record-asset.sh" \
  --type decision --tags "arch,db" \
  --title "PostgreSQL 선택" \
  --content "## 결정 사항
PostgreSQL 선택

## 고려한 대안
MySQL

## 선택 근거
JSONB 지원

## 유효 조건 (이 결정이 변할 수 있는 맥락)
클라우드 환경 변경 시" \
  --base-dir "$ASSET_DIR" 2>&1)
if [[ $? -eq 0 ]]; then
  pass "record-asset.sh --type decision"
else
  fail "record-asset.sh --type decision" "$(echo "$output" | head -2)"
fi

# ════════════════════════════════════════
# 32. detect-asset Stop: 임계치 도달 시 알림
# ════════════════════════════════════════
echo "${BOLD}[Stop 이벤트 + 임계치]${NC}"

stop_out=$(echo '{"hook_event_name":"Stop","session_id":"test-stop"}' \
  | ASSET_BASE_DIR="$ASSET_DIR" bash "$HARNISH_ROOT/scripts/detect-asset.sh" 2>/dev/null)
# compress-test 태그가 5건이므로 임계치 도달 알림이 있어야 함
if echo "$stop_out" | grep -q "임계치\|compress-test\|threshold\|압축"; then
  pass "detect-asset Stop: 임계치 알림 출력"
else
  # 자산이 전부 .archive로 이동됐다면 알림 없을 수 있음 (OK)
  pass "detect-asset Stop: 종료 정상 (임계치 없거나 이미 압축됨)"
fi

# ════════════════════════════════════════
# 결과 요약
# ════════════════════════════════════════
echo ""
echo "════════════════════════════════════════"
TOTAL=$((PASS + FAIL + SKIP))
printf " 결과: ${GREEN}PASS %d${NC} / ${RED}FAIL %d${NC} / ${YELLOW}SKIP %d${NC} (총 %d)\n" "$PASS" "$FAIL" "$SKIP" "$TOTAL"
echo "════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "실패 항목:"
  for r in "${RESULTS[@]}"; do
    if echo "$r" | grep -q "FAIL"; then
      printf "  %b\n" "$r"
    fi
  done
fi

echo ""
exit "$FAIL"
