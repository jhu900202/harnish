# 스크립트 검증 기준

> ralphi가 shell script를 검증할 때 참조하는 상세 기준.
> harnish M5 이후 고도화 예정.

## 필수 요소

- shebang: `#!/usr/bin/env bash`
- `set -euo pipefail` 또는 동등한 에러 핸들링
- 인자 없이 실행 시 usage 출력

## POSIX 호환

- `grep -P` 사용 금지 → `grep -E` 사용
- `mapfile` 사용 금지 → `while read` 사용
- GNU 전용 플래그 금지

## 출력 포맷

소비자(SKILL.md 또는 다른 스크립트)가 파싱 가능한 형태:
- JSON (`--format json`)
- 텍스트 (`--format text`)
- 주입용 (`--format inject`)
