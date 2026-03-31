#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
ERRORS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

# Get staged files only
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

# --- 1. Shell lint (shellcheck) ---
echo "Shell lint"
SH_FILES=$(echo "$STAGED_FILES" | grep '\.sh$' || true)
if [ -n "$SH_FILES" ]; then
  if command -v shellcheck &>/dev/null; then
    for f in $SH_FILES; do
      if shellcheck -S warning "$REPO_ROOT/$f" 2>/dev/null; then
        pass "$f"
      else
        fail "$f"
      fi
    done
  else
    warn "shellcheck not installed — skipping (brew install shellcheck)"
  fi
else
  pass "no .sh files staged"
fi

# --- 2. JSON syntax ---
echo "JSON syntax"
JSON_FILES=$(echo "$STAGED_FILES" | grep '\.json$' || true)
if [ -n "$JSON_FILES" ]; then
  for f in $JSON_FILES; do
    if python3 -m json.tool "$REPO_ROOT/$f" >/dev/null 2>&1; then
      pass "$f"
    else
      fail "$f — invalid JSON"
    fi
  done
else
  pass "no .json files staged"
fi

# --- 3. SKILL.md frontmatter ---
echo "SKILL.md frontmatter"
SKILL_FILES=$(echo "$STAGED_FILES" | grep 'SKILL\.md$' || true)
if [ -n "$SKILL_FILES" ]; then
  for f in $SKILL_FILES; do
    filepath="$REPO_ROOT/$f"
    # Check frontmatter exists
    if ! head -1 "$filepath" | grep -q '^---$'; then
      fail "$f — missing frontmatter"
      continue
    fi
    # Extract frontmatter block
    fm=$(awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$filepath")
    # Check required fields
    has_name=$(echo "$fm" | grep -c '^name:' || true)
    has_desc=$(echo "$fm" | grep -c '^description:' || true)
    has_version=$(echo "$fm" | grep -c '^version:' || true)
    if [ "$has_name" -eq 0 ]; then
      fail "$f — missing 'name' in frontmatter"
    elif [ "$has_desc" -eq 0 ]; then
      fail "$f — missing 'description' in frontmatter"
    elif [ "$has_version" -eq 0 ]; then
      fail "$f — missing 'version' in frontmatter"
    else
      # Validate SemVer format (X.Y.Z)
      version_val=$(echo "$fm" | grep '^version:' | sed 's/^version:[[:space:]]*//')
      if echo "$version_val" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        pass "$f (v$version_val)"
      else
        fail "$f — invalid version format '$version_val' (expected X.Y.Z)"
      fi
    fi
  done
else
  pass "no SKILL.md files staged"
fi

# --- 4. Script executable permission ---
echo "Script permissions"
if [ -n "$SH_FILES" ]; then
  for f in $SH_FILES; do
    if [ -x "$REPO_ROOT/$f" ]; then
      pass "$f"
    else
      fail "$f — not executable (chmod +x)"
    fi
  done
else
  pass "no .sh files staged"
fi

# --- Result ---
echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}Pre-commit failed: $ERRORS error(s)${NC}"
  exit 1
else
  echo -e "${GREEN}Pre-commit passed${NC}"
  exit 0
fi
