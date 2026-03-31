# 코드 검증 기준

> ralpi가 구현 코드를 검증할 때 참조하는 기준.
> 다른 스킬의 존재를 전제하지 않는다. 주어진 아티팩트만으로 판단한다.
> **언어에 종속되지 않는다.** 파일 확장자로 언어를 감지하고 해당 도구를 선택한다.

## 0. 언어 감지 → 도구 매핑

파일 확장자로 언어를 감지한 뒤, 해당 언어의 도구를 사용한다.
프로젝트 설정 파일이 우선. 없으면 아래 기본 도구.

| 확장자 | 언어 | 타입 체크 | lint | 테스트 러너 | 의존성 위치 |
|--------|------|----------|------|-----------|-----------|
| `.py` | Python | `mypy`, `pyright` | `ruff`, `flake8` | `pytest` | `venv/`, `.venv/` |
| `.ts`, `.tsx` | TypeScript | `tsc --noEmit` | `eslint`, `biome` | `vitest`, `jest`, `npm test` | `node_modules/` |
| `.js`, `.jsx` | JavaScript | — | `eslint`, `biome` | `vitest`, `jest`, `npm test` | `node_modules/` |
| `.java` | Java | `javac` | `checkstyle`, `spotbugs` | `mvn test`, `gradle test` | `target/`, `build/` |
| `.kt`, `.kts` | Kotlin | `kotlinc` | `ktlint`, `detekt` | `gradle test` | `build/` |
| `.go` | Go | `go vet` | `golangci-lint` | `go test ./...` | `vendor/` (선택) |
| `.rs` | Rust | `cargo check` | `cargo clippy` | `cargo test` | `target/` |
| `.swift` | Swift | `swiftc` | `swiftlint` | `swift test` | `.build/` |
| `.dart` | Dart | `dart analyze` | `dart analyze` | `dart test` | `.dart_tool/` |

**도구 선택 규칙:**

1. 프로젝트 설정 파일 확인 (`pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `build.gradle` 등)
2. 설정에 명시된 도구 우선 사용
3. 설정 없으면 위 표의 기본 도구 사용
4. 도구가 설치되어 있지 않으면 해당 검사 SKIP + 경고

**테스트 파일 패턴:**

| 언어 | 테스트 파일 패턴 |
|------|--------------|
| Python | `test_*.py`, `*_test.py`, `tests/` |
| TypeScript/JS | `*.test.ts`, `*.spec.ts`, `__tests__/` |
| Java | `*Test.java`, `*Tests.java`, `src/test/` |
| Kotlin | `*Test.kt`, `src/test/` |
| Go | `*_test.go` (동일 패키지) |
| Rust | `#[cfg(test)]` 모듈, `tests/` |
| Swift | `*Tests.swift`, `Tests/` |

## 1. 구조적 완성도 (정적 분석)

### 1.1 파일 자체 품질

- 타입 체크 통과 (§0 도구 매핑 참조)
- lint 통과 (§0 도구 매핑 참조 — 프로젝트 설정 존재 시)
- 하드코딩된 시크릿 없음 (API 키, 비밀번호, 토큰 패턴 grep)
- 매직 넘버 없음 (설정 가능한 값은 config로 분리됐는가)
- dead code 없음 (미사용 import, 미호출 함수)

### 1.2 에러 핸들링

- 외부 호출(DB, API, 파일 I/O)에 에러 처리 존재
  - Python: `try/except`
  - TypeScript/JavaScript/Java/Kotlin/Swift/Dart: `try/catch`
  - Go: `if err != nil`
  - Rust: `Result<T, E>` / `?` 연산자
- 에러 시 적절한 응답/로깅 (빈 에러 핸들러 금지)
- 예상 가능한 실패 경로가 핸들링됨

### 1.3 엣지 케이스

- null/nil/None/zero value 입력 처리 (언어별 null 표현에 대응)
- 빈 컬렉션/빈 문자열 처리
- 경계값 (0, 음수, 최대값) 처리
- 동시성 이슈 (해당되는 경우)

## 2. 기능적 완성도 (동적 실행)

### 2.1 테스트 존재 및 통과

- 대응하는 테스트 파일 존재 여부 (§0 테스트 파일 패턴 참조)
- 테스트 실행 (§0 도구 매핑 참조)
- 테스트 커버리지: 핵심 로직 경로가 테스트됨

### 2.2 실제 동작 검증

- 해당 코드의 진입점을 찾아 실행 가능한가
- import/require/use/from 체인이 깨지지 않는가
- 의존성이 모두 설치돼 있는가 (§0 의존성 위치 참조)

## 3. 맥락 대조 (선택적 — 추가 아티팩트 제공 시)

사용자가 코드와 함께 PRD나 PROGRESS.json를 제공한 경우에만 수행.
제공하지 않으면 §1, §2만으로 검증한다.

### 3.1 PRD 제공 시

- PRD §4 파일 목록에 명시된 파일이 실제로 존재하는가
- PRD §6 테스트 기준이 테스트 코드에 반영됐는가
- PRD §7 금지사항이 코드에서 위반되지 않았는가

### 3.2 PROGRESS.json 제공 시

- Done 처리된 Task의 acceptance_criteria가 실제로 충족됐는가
- 변경 파일 목록과 실제 변경이 일치하는가

## 4. 검증 순서

```
1. §0 언어 감지 + 도구 확인
2. §1.1 파일 자체 품질 → 이슈 있으면 수정
3. §1.2 에러 핸들링 → 이슈 있으면 수정
4. §1.3 엣지 케이스 → 이슈 있으면 수정
5. §2.1 테스트 존재 및 통과 → 실패 시 수정
6. §2.2 실제 동작 검증 → 실패 시 수정
7. (PRD/PROGRESS.json 제공 시) §3 맥락 대조
8. 모든 항목 PASS → 검증 완료
```
