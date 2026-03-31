# Versioning Policy

## Overview

harnish는 **혼합 버저닝**을 사용한다.

- **리포 버전** (`VERSION`): 프로젝트 전체의 릴리스 식별자
- **스킬 버전** (각 `SKILL.md` frontmatter `version:`): 개별 스킬의 변경 추적

모두 [Semantic Versioning 2.0.0](https://semver.org/)을 따른다.

## SemVer 규칙: `MAJOR.MINOR.PATCH`

| 구분 | 언제 올리는가 | 예시 |
|------|-------------|------|
| **MAJOR** | 호환 불가 변경 (스킬 API, 스크립트 인터페이스 breaking) | 1.0.0 |
| **MINOR** | 기능 추가 (새 스킬, 새 스크립트, 기존 스킬 기능 확장) | 0.1.0 |
| **PATCH** | 버그 수정, 문서 수정, 리팩토링 | 0.0.2 |

## Version Bump 규칙

| 변경 대상 | 리포 버전 | 스킬 버전 |
|-----------|----------|----------|
| 특정 스킬의 버그 수정 | PATCH | 해당 스킬 PATCH |
| 특정 스킬에 기능 추가 | MINOR | 해당 스킬 MINOR |
| 공유 스크립트(scripts/) 변경 | MINOR | 영향받는 스킬 PATCH |
| 새 스킬 추가 | MINOR | 새 스킬 `0.0.1` |
| 호환 불가 변경 | MAJOR | 해당 스킬 MAJOR |
| 문서만 변경 (README, CHANGELOG) | — (bump 안 함) | — |

## 파일 위치

```
harnish/
├── VERSION                          ← 리포 버전 (한 줄: "0.0.1")
├── CHANGELOG.md                     ← Keep a Changelog 포맷
├── VERSIONING.md                    ← 이 문서
└── skills/
    ├── drafti-architect/SKILL.md    ← frontmatter version: 0.0.1
    ├── drafti-feature/SKILL.md      ← frontmatter version: 0.0.1
    ├── harnish/SKILL.md             ← frontmatter version: 0.0.1
    └── ralphi/SKILL.md              ← frontmatter version: 0.0.1
```

## Git Tag

- 형태: `v{MAJOR}.{MINOR}.{PATCH}` (예: `v0.0.1`)
- 시점: **PR이 main에 머지될 때** 생성
- 명령: `git tag -a v0.0.1 -m "Release 0.0.1"` → `git push origin v0.0.1`

## CHANGELOG 작성 규칙

1. **포맷**: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
2. **섹션**: Added, Changed, Fixed, Removed, Deprecated, Security
3. **스킬별 서브그룹**: `#### drafti-architect`, `#### harnish` 등
4. **Unreleased**: 상시 유지. 릴리스 시 날짜와 함께 확정
5. **스킬 버전 표기**: 섹션 제목에 스킬 버전 병기 (예: `#### ralphi \`0.0.2\``)

## 릴리스 절차

```
1. 변경 작업 완료
2. CHANGELOG.md [Unreleased] → [X.Y.Z] - YYYY-MM-DD 로 확정
3. VERSION 파일 업데이트
4. 변경된 스킬의 SKILL.md frontmatter version 업데이트
5. 커밋: "chore: release vX.Y.Z"
6. PR 생성 → 리뷰 → 머지
7. main에서 태그: git tag -a vX.Y.Z -m "Release X.Y.Z"
8. 태그 푸시: git push origin vX.Y.Z
```

## 커밋 정책

- `Co-Authored-By` 트레일러를 커밋 메시지에 포함하지 않는다
- 커밋 author는 git config의 사용자 정보를 그대로 사용한다 (Claude 표기 금지)
- 커밋 메시지는 [Conventional Commits](https://www.conventionalcommits.org/) 형식을 따른다
  - `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`

## Pre-commit 검증

`scripts/pre-commit.sh`가 커밋 시 자동으로 검증:
- SKILL.md frontmatter에 `version:` 필드 존재 여부
- `version:` 값이 SemVer 패턴 (`X.Y.Z`) 인지 확인
