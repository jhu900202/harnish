# PROGRESS.json 스키마

> harnish 스킬이 PROGRESS.json을 생성/갱신할 때 참조하는 구조.
> 이 파일은 세션 간 맥락 보존의 핵심이다.

---

## JSON 스키마

```json
{
  "metadata": {
    "prd": "docs/prd-{slug}.md",
    "started_at": "YYYY-MM-DDTHH:MM:SS+09:00",
    "last_session": "YYYY-MM-DDTHH:MM:SS+09:00",
    "status": {
      "emoji": "🟢",
      "phase": 1,
      "task": "1-1",
      "label": "정상 진행 중"
    }
  },
  "done": {
    "phases": [
      {
        "phase": 1,
        "title": "페이즈 제목",
        "compressed": false,
        "milestone_approved_at": "YYYY-MM-DDTHH:MM:SS+09:00",
        "tasks": [
          {
            "id": "1-1",
            "title": "태스크 제목",
            "result": "무엇을 했는가 — 한 줄",
            "files_changed": ["파일1", "파일2"],
            "verification": "어떻게 확인했는가 — 명령어 또는 조건",
            "duration": "대략적 턴 수 또는 시간"
          }
        ]
      }
    ]
  },
  "doing": {
    "task": null
  },
  "todo": {
    "phases": [
      {
        "phase": 2,
        "title": "페이즈 제목",
        "tasks": [
          {
            "id": "2-1",
            "title": "태스크 제목",
            "depends_on": []
          }
        ]
      }
    ]
  },
  "issues": [],
  "violations": [],
  "escalations": [],
  "stats": {
    "total_phases": 0,
    "completed_phases": 0,
    "total_tasks": 0,
    "completed_tasks": 0,
    "issues_count": 0,
    "violations_count": 0
  }
}
```

## 필드 설명

### metadata.status

| emoji | 의미 |
|-------|------|
| 🟢 | 정상 진행 중 |
| 🟡 | 진행 중이나 이슈 있음 |
| 🔴 | 블로커 발생, 에스컬레이션 필요 |
| ✅ | 전체 완료 |

### doing.task

활성 태스크가 있으면 객체, 없으면 `null`.

```json
{
  "id": "1-2",
  "title": "API 엔드포인트 생성",
  "started_at": "YYYY-MM-DDTHH:MM:SS+09:00",
  "current": "지금 뭘 하고 있는가",
  "last_action": "가장 최근 수행한 것",
  "next_action": "바로 다음에 할 것",
  "blocker": null,
  "retry_count": 0,
  "context": {
    "guide": "guide.objective 요약",
    "scope": "guardrails.scope 요약",
    "prd_reference": "PRD §4.1"
  }
}
```

### done.phases[] — 압축된 Phase

```json
{
  "phase": 1,
  "title": "데이터 모델",
  "compressed": true,
  "compressed_summary": "tasks:4 | files:src/models/*.ts",
  "archive_ref": ".progress-archive/phases.jsonl#phase=1"
}
```

---

## 갱신 규칙

### 태스크 시작 시

1. `todo.phases[].tasks[]`에서 해당 태스크를 제거
2. `doing.task`에 태스크 객체 설정 (started_at, context 포함)
3. `metadata.status` 갱신

### 3액션마다

`doing.task`의 `current`, `last_action`, `next_action` 갱신.
이 갱신은 세션 중단 시 복원 지점 역할을 한다.

### 태스크 완료 시

1. `doing.task`를 `done.phases[].tasks[]`에 추가 (result, files_changed, verification, duration 포함)
2. `doing.task`를 `null`로 설정
3. `stats.completed_tasks` 증가
4. 마일스톤이면 체크포인트 보고서 생성

### 에러 발생 시

1. `issues[]`에 추가
2. `doing.task.blocker` 설정
3. `doing.task.retry_count` 증가

### 마일스톤 도달 시

1. `stats` 갱신
2. 체크포인트 보고서 생성 (progress-report.sh)
3. 사용자 승인 요청
4. `done.phases[].milestone_approved_at` 기록

### 세션 시작 시

1. PROGRESS.json 읽기
2. `doing.task`이 non-null이면 `next_action`부터 재개
3. `doing.task`이 null이면 `todo.phases`에서 다음 태스크 선택
4. 사용자에게 간략히 보고
