# forki — 자산 영구화 (Step 0 + Step 8 상세)

> `forki/SKILL.md`가 Step 0(과거 결정 조회) 또는 Step 8(자산 기록) 진입 시 로드.

## Step 0 — 과거 결정 조회

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$HARNISH_ROOT/scripts/query-assets.sh" --types decision --tags "{주제}" --format text --base-dir "$(pwd)/.harnish" 2>/dev/null || true
```

- `.harnish/`가 없거나 출력이 비어있으면(매칭 없음) 생략.
- 매칭이 있으면 → `references/protocol.md`의 Step 0 HITL 프롬프트로 사용자에게 제시.
- `trust` → forki 종료, **Reused** 보고 템플릿 출력 (`references/protocol.md` 참조).
- `reopen` → 정상적으로 Step 1로 진행.

## Step 8 — Decision 자산 기록

### 8.0 — Pre-check

CWD에 `.harnish/`가 없으면 → Step 8 전체 생략. 보고 `not-persisted: no .harnish in CWD`. **forki는 `.harnish/`를 초기화하지 않는다.**

### 8.1 — HITL 프롬프트 (어떤 쓰기 동작보다도 먼저)

LLM이 기본 태그를 먼저 제안한 후 (kebab-case, binary 주제에서 유도) `references/protocol.md`의 Step 8 프롬프트로 묻는다.

분기:
- `n` → Step 8 종료, 보고 `skipped (user opt-out)`. **파일 작성 금지.**
- `edit-tags` → 묻기: *"태그? (콤마, kebab-case)"* → 그것 사용.
- `y` → 제안된 기본 태그 사용.

`y`와 `edit-tags` 두 경우 모두 결과 태그 문자열 = `TAGS` (LLM이 literal 문자열로 보유, shell 변수 아님).

### 8.2 — body 작성 + 자산 기록 (단일 bash 호출)

치환 전 LLM이 해야 할 것:
- `TAGS`와 `TITLE`: 안의 `"`, `$`, `` ` ``, `\` 각각 앞에 `\` 추가 (bash 더블쿼트 안에서 안전)
- `BODY_CONTENT`: 어느 라인도 정확히 `FORKI_REPORT_EOF`와 일치하지 않게. 일치하면 그 라인을 다시 생성하여 문자열을 깨뜨림 (예: 두 줄로 분할). heredoc 태그 이름을 바꾸지 **말 것**.

그 후 **단일** bash 블록 실행:

```bash
HARNISH_ROOT="${CLAUDE_PLUGIN_ROOT}"
BODY="/tmp/forki-$(date -u +%Y%m%dT%H%M%SZ).md"
cat > "$BODY" <<'FORKI_REPORT_EOF'
{BODY_CONTENT}
FORKI_REPORT_EOF
if bash "$HARNISH_ROOT/scripts/record-asset.sh" --type decision --tags "{TAGS}" --title "{TITLE}" --body-file "$BODY" --base-dir "$(pwd)/.harnish"; then
  echo "FORKI_RESULT: recorded"
else
  echo "FORKI_RESULT: record-failed (body kept at $BODY)"
fi
```

heredoc 태그가 quoted (`'FORKI_REPORT_EOF'`)이므로 `BODY_CONTENT` 안의 `$`나 backtick은 확장되지 않는다. timestamp는 같은 bash 호출 안에서 계산 (사전 치환 단계 없음).

`FORKI_RESULT:` 줄을 읽고 default 보고의 Asset 섹션에 그대로 기록 (`references/protocol.md` 참조).

**부수효과지 게이트 아님**: Step 6 verdict는 Step 8 결과와 무관하게 유효.

## 무엇이 어디에 쓰이는가

| 파일 | 포맷 | 목적 |
|---|---|---|
| `/tmp/forki-{ts}.md` | Markdown | 보고 본문 전체, `record-asset.sh --body-file`에 전달 |
| `.harnish/assets/decision-{date}.jsonl` | JSONL (1줄/asset) | 영구 자산 저장소, Step 0가 조회 |
