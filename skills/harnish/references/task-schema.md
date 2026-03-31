# 태스크 YAML 스키마

> 태스크 시딩 결과물의 구조 정의.
> PROGRESS.json에 인라인으로 기록하거나, 별도 YAML 파일로 관리할 수 있다.

---

## 전체 구조

```yaml
project:
  name: "{프로젝트명}"
  prd: "{PRD 파일 경로}"
  created: "{YYYY-MM-DD}"

  # 프로젝트 레벨 가드레일 (PRD §7에서 도출)
  guardrails:
    architecture:
      - "{규칙 1}"
    code_style:
      - "{규칙 1}"
    testing:
      - "{규칙 1}"

  # 프로젝트 레벨 금지사항
  prohibitions:
    - id: "{NO_SOMETHING}"
      rule: "{규칙}"
      on_violation: "{즉시 중단, 사용자에게 보고}"

phases:
  - id: 1
    title: "{페이즈 제목}"
    objective: "{이 페이즈의 목적}"
    completion_condition: "{페이즈 완료 조건}"

    tasks:
      - id: "1-1"
        title: "{태스크 제목}"
        estimated_effort: "small"  # small | medium | large
        depends_on: []

        guide:
          objective: "{이 태스크의 목적}"
          strategy: "{접근 방법}"
          target_files:
            - path: "{파일 경로}"
              action: "{수정/생성/삭제}"
          reference: "{PRD 섹션 참조}"
          context: "{전후 관계 설명}"

        acceptance_criteria:
          - "{검증 조건 1}"
          - "{검증 조건 2}"

        guardrails:
          scope:
            - "{수정 가능 범위}"
          decisions:
            - "{따라야 할 규칙}"

        prohibitions:
          - "{금지 사항}"

    milestone:
      gate: "{마일스톤 통과 조건}"
      requires_approval: true
      report_includes:
        - "완료 태스크 요약"
        - "변경 파일 목록"
        - "이슈/결정 로그"
        - "다음 페이즈 개요"
```

## 필드 설명

### guide (가이드)

| 필드 | 필수 | 설명 |
|------|------|------|
| objective | 필수 | 이 태스크가 완료되면 어떤 상태인가 |
| strategy | 권장 | 어떤 접근법을 쓸 것인가 |
| target_files | 필수 | 어떤 파일을 대상으로 하는가 |
| reference | 권장 | PRD의 어떤 섹션을 참조하는가 |
| context | 권장 | 이전/이후 태스크와의 관계 |

guide는 "길 안내"다. 구체적이고 실행 가능해야 한다.

나쁜 예: "모델을 추가하세요"
좋은 예: "src/schema.prisma 파일의 model User {} 블록 아래에 Post 모델을 추가한다. PRD §3.2의 필드 목록을 따른다."

### acceptance_criteria (검증 기준)

가능하면 실행 가능한 명령으로 표현한다:
- "npm test -- --grep 'User model' 실행 시 3개 테스트 통과"
- "prisma validate 실행 시 에러 없음"
- "curl localhost:3000/api/users 응답 200"

실행 불가능한 경우 확인 가능한 조건으로:
- "src/models/user.ts 파일에 User interface가 정의되어 있음"
- "모든 필드에 타입이 명시되어 있음"

### guardrails vs prohibitions

| | guardrails (soft) | prohibitions (hard) |
|---|---|---|
| 위반 시 | 경고 후 교정 | 즉시 중단 |
| 용도 | 방향 안내 | 절대 금지 |
| 예시 | "schema.prisma만 수정" | "마이그레이션 실행 금지" |

### estimated_effort

| 값 | 의미 | 대략적 시간 |
|----|------|-----------|
| small | 파일 1개, 간단한 변경 | ~15분 |
| medium | 파일 1~3개, 로직 포함 | ~30분 |
| large | 파일 3개+, 복잡한 로직 | ~1시간 |

large를 넘어가면 태스크를 분할해야 한다.

### depends_on

선행 태스크 ID의 배열. 선행 태스크가 모두 완료되어야 이 태스크 실행 가능.
의존성이 없으면 빈 배열 `[]`.

의존성 규칙:
- 같은 페이즈 내 태스크끼리만 의존 (페이즈 간 의존은 마일스톤으로)
- 순환 의존 금지
- 의존성이 없는 태스크는 순서 자유 (병렬 실행 가능)
