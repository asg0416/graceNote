# GraceNote Phase 2C UI/App Smoke Checklist

> Purpose: Phase 2C 운영 반영 전, DB rollback 검증으로는 확인할 수 없는 관리자 웹/앱 화면 흐름을 실제 UI 기준으로 확인한다.

## Current Scope

현재 smoke는 운영 서버가 아니라 개발 서버 기준으로 진행한다. 운영 DB에는 쓰기 작업을 하지 않는다.

| Area | Owner | Why |
| --- | --- | --- |
| DB rollback verification | Codex | SQL로 legacy/Phase 2 write sync를 자동 검증 |
| Code/diff review | Codex | 운영 후보 파일이 의도한 범위만 바꾸는지 확인 |
| Browser UI operation | User | 로그인 세션, 모달, 버튼, 화면 메시지는 실제 브라우저에서만 확정 가능 |
| Result logging | Codex | 결과를 manifest/Notion issue registry에 기록 |

## Already Automated

2026-05-04 기준 아래 항목은 Codex가 dev DB에서 rollback 검증했다.

| Check | Result |
| --- | --- |
| `verify_phase2_member_directory_write_flow_dev_2026-05-03.sql` | 통과 |
| `verify_phase2_regrouping_write_flow_dev_2026-05-02.sql` | 통과 |
| `verify_phase2_smart_batch_write_flow_dev_2026-05-03.sql` | 통과 |
| `verify_phase2_member_directory_trigger_columns_dev_2026-05-01.sql` | 통과 |
| `verify_phase2_consistency_dev_2026-04-30.sql` | missing/mismatch 0 |

## User Browser Smoke Checklist

아래는 사용자가 실제 관리자 웹/앱에서 확인해야 하는 항목이다. 각 항목은 “성공 기준”만 확인하면 된다. 실패하면 화면 메시지와 어떤 교회/부서/조/성도에서 발생했는지만 알려주면 된다.

### 1. 성도명부 목록

- [ ] 교회를 장전제일교회로 선택한다.
- [ ] Phase 2 목록 진단이 `일치` 또는 issues 0으로 보이는지 확인한다.
- [ ] 교회를 graceChurch로 바꾼다.
- [ ] Phase 2 목록 진단이 `일치` 또는 issues 0으로 보이는지 확인한다.
- [ ] 교회 전환 직후 진단이 이전 교회 상태로 흔들리지 않는지 확인한다.

성공 기준:
- legacy/Phase 2 숫자가 같은 방향으로 움직인다.
- 다른 교회 성도가 현재 교회 목록/진단에 섞이지 않는다.

### 2. 성도상세

- [ ] 여러 조에 속한 성도 1명을 연다.
- [ ] Phase 2 패널에서 같은 사람의 active memberships가 현재 화면의 의미와 맞는지 확인한다.
- [ ] inactive/ended history가 현재 소속처럼 보이지 않는지 확인한다.
- [ ] 다른 교회 소속이 상세 패널에 섞이지 않는지 확인한다.

성공 기준:
- active는 현재 소속만 보인다.
- ended/inactive는 이력으로 분리되어 보인다.

### 3. 조편성

- [ ] 기존 성도 1명을 다른 조로 이동하고 저장한다.
- [ ] legacy/Phase 2 진단 숫자가 함께 움직이는지 확인한다.
- [ ] 같은 사람의 여러 카드를 같은 신규 조에 동시에 넣어 저장 전 차단되는지 확인한다.
- [ ] 복사된 성도를 제거했을 때 Phase 2 issue가 생기지 않는지 확인한다.
- [ ] 조편성 헤더의 전체 성도 수가 카드 수가 아니라 실제 사람 수 기준으로 보이는지 확인한다.

성공 기준:
- 중복 편성은 저장 전 한국어 메시지로 차단된다.
- 저장 후 Phase 2 진단 issue가 0이다.

### 4. SmartBatch 대량등록

- [ ] 현재 교회에서 대량등록 모달을 연다.
- [ ] 기존 성도 후보 검색이 현재 교회 active 성도만 보여주는지 확인한다.
- [ ] 같은 사람이 여러 부서/조 row를 가져도 후보가 불필요하게 반복되지 않는지 확인한다.
- [ ] 테스트 성도 2명을 새 조 또는 기존 조에 대량 등록한다.
- [ ] 저장 후 성도명부/조편성 Phase 2 진단이 issue 0인지 확인한다.

성공 기준:
- cross-church 후보가 표시되지 않는다.
- 대량 등록 후 legacy/Phase 2 count가 일치한다.

### 5. 부서/조 종료

- [ ] 테스트용 조를 하나 만든다.
- [ ] 조 종료를 실행한다.
- [ ] `오류가 발생했습니다`가 뜨지 않는지 확인한다.
- [ ] 종료된 조가 기본 목록/조편성 대상에서 빠지는지 확인한다.
- [ ] 가능하면 테스트용 부서도 종료해 보고, active 목록에서 빠지는지 확인한다.

성공 기준:
- hard delete가 아니라 종료/비활성화로 동작한다.
- 종료된 조/부서가 active 화면에 남지 않는다.

### 6. Flutter 앱 주차/예배 흐름

- [ ] 앱에서 주차/예배 없음 또는 주차 삭제에 해당하는 흐름을 확인한다.
- [ ] 기존 출석/기도/뉴스레터가 사라지지 않는지 확인한다.
- [ ] 비활성화된 주차가 일반 선택 목록에 계속 노출되지 않는지 확인한다.

성공 기준:
- 주차는 hard delete되지 않고 `is_active=false` 의미로 처리된다.
- 과거 기록은 보존된다.

## If Something Fails

실패 시 아래 형식으로 알려주면 된다.

```plain text
화면:
교회:
부서/조:
성도:
내가 한 동작:
화면 메시지:
legacy 숫자:
Phase 2 숫자:
```

Codex는 이 정보를 기준으로 DB 상태, 코드 경로, Notion issue registry를 같이 업데이트한다.

## Next After Smoke

| Result | Next |
| --- | --- |
| All smoke green | Phase 2C dev 기준 완료 후보. prod-safe verification SQL 준비 |
| Minor UI-only issue | UI fix 후 해당 smoke만 재검증 |
| DB mismatch issue | 새 migration/trigger 보정 후 rollback verify 재실행 |
| Permission/RLS issue | Phase 2 read policy 보정 후 admin/master smoke 재검증 |
