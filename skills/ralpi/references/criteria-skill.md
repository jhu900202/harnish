# SKILL.md 검증 기준

> ralpi가 SKILL.md 아티팩트를 검증할 때 참조하는 상세 기준.
> harnish M5 이후 고도화 예정.

## frontmatter

- `name`: 필수. 케밥 케이스.
- `version`: 필수. SemVer 포맷 (`X.Y.Z`). pre-commit 훅이 검증함.
- `description`: 필수. 1줄 이상.

## 모호 표현

SKILL.md에 모호 표현이 있으면 저수준 모델이 판단을 시작한다. 이는 위험하다.
모든 조건문은 if/then 형태로 명확해야 한다.

## bash 경로 검증

`${CLAUDE_SKILL_DIR}` 또는 `$HARNISH_ROOT` 기반 경로가 실제 존재하는지 확인.

## 맥락 예산

맥락 예산 섹션이 존재해야 한다. 어떤 reference를 언제 읽는지 명시.
