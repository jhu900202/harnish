#!/usr/bin/env bash
# common.sh — L1 Storage: 공용 함수 라이브러리
#
# Layer: L1 (Storage)
# 역할: 디렉토리·인덱스 관리, 환경 해석, 유틸리티 함수
# 규칙: L2 이상의 스크립트를 호출하지 않는다.
#
# 사용법 (다른 스크립트에서):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/common.sh"

# ═══════════════════════════════════════
# 의존성 체크
# ═══════════════════════════════════════
require_cmd() {
    local cmd="$1" install_hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        echo "오류: '$cmd'이(가) 설치되어 있지 않습니다.${install_hint:+ $install_hint}" >&2
        exit 1
    fi
}

require_cmd jq "brew install jq"

# ═══════════════════════════════════════
# 환경 해석
# ═══════════════════════════════════════
# 이 파일이 source된 스크립트의 SCRIPT_DIR을 기준으로 한다.
# SCRIPT_DIR은 source하기 전에 설정되어야 한다.

# 자산 루트 경로 해석
# 우선순위: ASSET_BASE_DIR > CLAUDE_PROJECT_DIR/_base/assets > 스크립트 상대경로
resolve_base_dir() {
    if [[ -n "${ASSET_BASE_DIR:-}" ]]; then
        echo "$ASSET_BASE_DIR"
    elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        echo "${CLAUDE_PROJECT_DIR}/_base/assets"
    else
        local harnish_root
        harnish_root="$(cd "${SCRIPT_DIR:-$(pwd)}/.." && pwd)"
        local parent
        parent="$(cd "$harnish_root/.." && pwd)"
        echo "$parent/_base/assets"
    fi
}

# 스킬 디렉토리 (references/ 접근용)
resolve_skill_dir() {
    echo "$(cd "${SCRIPT_DIR:-$(pwd)}/../skills/harnish" && pwd)"
}

# sections.json 경로
resolve_sections_file() {
    echo "$(resolve_skill_dir)/references/sections.json"
}

# ═══════════════════════════════════════
# 슬러그 생성 — 비ASCII 안전
# ═══════════════════════════════════════
# 1차: ASCII 변환 → 유효한 slug면 사용
# 2차: 비ASCII(한국어 등)면 md5 해시 앞 12자
slugify() {
    local input="$1"
    local ascii_slug
    ascii_slug=$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-60)
    if [[ -n "$ascii_slug" && "$ascii_slug" != "-" ]]; then
        echo "$ascii_slug"
    else
        local hash
        hash=$(echo -n "$input" | md5sum | cut -c1-12)
        echo "$hash"
    fi
}

# ═══════════════════════════════════════
# YAML 태그 포맷 — 따옴표로 감싸서 YAML 규격 준수
# ═══════════════════════════════════════
# 입력: "api,retry,http-client"
# 출력: ["api", "retry", "http-client"]
format_yaml_tags() {
    local raw="$1"
    if [[ -z "$raw" ]]; then
        echo "[]"
        return
    fi
    local result=""
    IFS=',' read -ra items <<< "$raw"
    for item in "${items[@]}"; do
        item=$(echo "$item" | xargs)
        [[ -z "$item" ]] && continue
        if [[ -n "$result" ]]; then
            result="${result}, \"${item}\""
        else
            result="\"${item}\""
        fi
    done
    echo "[${result}]"
}

# ═══════════════════════════════════════
# Frontmatter 파싱 — 파일에서 YAML frontmatter만 추출
# ═══════════════════════════════════════
# 입력: 파일 경로
# 출력: frontmatter 본문 (--- 제외)
parse_frontmatter() {
    local file="$1"
    awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$file"
}

# 입력: 파일 경로
# 출력: body 본문 (frontmatter 제외)
parse_body() {
    local file="$1"
    sed -n '/^---$/,/^---$/!p' "$file" | sed '1{/^$/d;}'
}

# frontmatter에서 특정 필드 추출
# 사용: get_field "$frontmatter" "type"
get_field() {
    local fm="$1" field="$2"
    echo "$fm" | grep -E "${field}:" 2>/dev/null | head -1 | sed "s/.*${field}:[[:space:]]*//" | sed 's/^"//; s/"$//' || echo ""
}

# frontmatter에서 tags 배열 추출 (따옴표 제거)
get_tags() {
    local fm="$1"
    echo "$fm" | grep -E 'tags:' 2>/dev/null | head -1 | sed 's/.*tags:[[:space:]]*\[//' | sed 's/\].*//' || echo ""
}

# ═══════════════════════════════════════
# Index.json 관리 — atomic write
# ═══════════════════════════════════════
# index를 안전하게 갱신한다 (임시파일 + mv)
# 사용: atomic_write_index "$INDEX_FILE" "$UPDATED_JSON"
atomic_write_index() {
    local index_file="$1" content="$2"
    echo "$content" > "${index_file}.tmp" && mv "${index_file}.tmp" "$index_file"
}

# ═══════════════════════════════════════
# 폴더 매핑
# ═══════════════════════════════════════
# type → folder 변환
type_to_folder() {
    local type="$1"
    case "$type" in
        pattern)   echo "patterns";;
        failure)   echo "failures";;
        guardrail) echo "guardrails";;
        snippet)   echo "snippets";;
        decision)  echo "decisions";;
        compressed) echo ".compressed";;
        *) echo "";;
    esac
}

# ═══════════════════════════════════════
# 로깅
# ═══════════════════════════════════════
asset_log() {
    local base_dir="$1" msg="$2"
    local log_file="${base_dir}/.meta/hook.log"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p "$(dirname "$log_file")" 2>/dev/null
    echo "[${ts}] $msg" >> "$log_file" 2>/dev/null || true
}
