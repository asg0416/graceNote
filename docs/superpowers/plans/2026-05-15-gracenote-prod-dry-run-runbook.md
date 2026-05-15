# GraceNote Prod Dry-Run Runbook

> Purpose: 운영 적용 전, 운영 복제본 또는 fresh DB에서 Phase 2/3 migration과 verification gate를 같은 순서로 반복 실행하기 위한 절차다.

## Rule

- 운영 DB에 직접 쓰지 않는다.
- 운영 복제본, staging DB, 또는 local fresh DB에서만 dry-run한다.
- DB URL, access token, service role key는 repo에 저장하지 않는다.
- 성공 기준은 기억이 아니라 verification script output과 smoke checklist다.

## Current Gate Script

먼저 migration 파일과 manifest 실행표가 일치하는지 확인한다.

```bash
node scripts/preprod-check-migration-inventory.mjs
```

그 다음 DB verification gate를 실행한다.

```bash
node scripts/preprod-verify-gates.mjs --local
```

대상 DB URL이 있을 때:

```bash
read -s GRACENOTE_VERIFY_DB_URL
export GRACENOTE_VERIFY_DB_URL
node scripts/preprod-verify-gates.mjs
unset GRACENOTE_VERIFY_DB_URL
```

또는 임시 파일을 사용할 때:

```bash
read -s GRACENOTE_VERIFY_DB_URL
printf '%s' "$GRACENOTE_VERIFY_DB_URL" > /private/tmp/gracenote_verify_db_url
unset GRACENOTE_VERIFY_DB_URL
node scripts/preprod-verify-gates.mjs --db-url-file /private/tmp/gracenote_verify_db_url
```

그 다음 운영 복제본 데이터 감사 SQL을 실행한다. 이 단계는 기존 운영 데이터의 꼬임을 적용 전에 분류하기 위한 read-only 점검이다.

```bash
supabase db query --db-url "$GRACENOTE_VERIFY_DB_URL" --file supabase/preprod_data_audit_summary_2026-05-15.sql --output table
supabase db query --db-url "$GRACENOTE_VERIFY_DB_URL" --file supabase/preprod_auto_repair_candidates_2026-05-15.sql --output table
supabase db query --db-url "$GRACENOTE_VERIFY_DB_URL" --file supabase/preprod_manual_review_candidates_2026-05-15.sql --output table
```

임시 파일을 사용할 때는 `--db-url "$(cat /private/tmp/gracenote_verify_db_url)"`로 실행한다. 이 파일들은 read-only이며 운영 DB에 직접 실행하지 않는다.

## Gate List

| Gate | Expected |
| --- | --- |
| `scripts/preprod-check-migration-inventory.mjs` | manifest의 prod candidate migration 파일이 실제 파일과 일치 |
| `verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql` | all `issue_count = 0` |
| `verify_phase2_consistency_summary_dev_2026-05-10.sql` | all `issue_count = 0` |
| `verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql` | all `issue_count = 0` |
| `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql` | all `issue_count = 0` |
| `verify_app_config_rls_dev_2026-05-15.sql` | all `issue_count = 0` |
| `verify_phase2d_edge_notification_targets_dev_2026-05-09.sql` | all `mismatch_count = 0` |

## Preprod Data Audit

| SQL | Expected | Action |
| --- | --- | --- |
| `preprod_data_audit_summary_2026-05-15.sql` | `blocking_gate = 0` | nonzero면 운영 반영 중단 |
| `preprod_data_audit_summary_2026-05-15.sql` | `auto_repair_candidate`는 0이 아니어도 가능 | 운영 복제본에서 repair SQL을 작성/검증하고 승인된 항목만 prod 적용 |
| `preprod_data_audit_summary_2026-05-15.sql` | `manual_review`는 0이 아니어도 가능 | 자동 병합 금지. 운영자 확인 목록으로 관리 |
| `preprod_auto_repair_candidates_2026-05-15.sql` | 자동 보정 후보 상세 | 실제 UPDATE SQL이 아니라 보정 설계 입력 |
| `preprod_manual_review_candidates_2026-05-15.sql` | 전화번호/이름/profile church mismatch 후보 상세 | 자동 수정 금지 |

2026-05-15 local syntax check:
- `preprod_data_audit_summary_2026-05-15.sql`: executed on local DB, all counts `0`.
- `preprod_auto_repair_candidates_2026-05-15.sql`: executed on local DB, 0 rows.
- `preprod_manual_review_candidates_2026-05-15.sql`: executed on local DB, 0 rows.

## Manual Smoke After DB Gates

| Surface | Smoke |
| --- | --- |
| Admin members | actual people count, active people count, member detail, edit, memo, family info |
| Admin SmartBatch | individual registration, AI batch registration, existing same-church person link, other-church duplicate isolation |
| Admin regrouping | move, copy, couple move, new group, add member, delete group, diagnostics issue 0 |
| Admin archive | person+department archive, selected group restore, duplicate restore prevention |
| Admin attendance | snapshot load, bulk load unsubmitted groups, include/exclude, attendance toggle, conflict resolution, export |
| Flutter master/admin/leader/member | role menu, group list, attendance save, prayer save, prayer search scope, saved prayers, deleted group history |
| Edge functions | `notify-event` and `notify-scheduler` deployed, `verify_jwt=false`, dry-run or limited real send |

## UI Polish Before Prod

운영 적용 전에 반드시 기능을 바꿀 필요는 없지만, 사용자가 DB 진단 정보를 그대로 보는 느낌을 줄이려면 아래를 정리한다.

| Area | Direction |
| --- | --- |
| 성도명부 통계 카드 | 운영 화면은 실제 성도 수 중심으로 단순화 |
| 성도상세 소속/이력 | 현재 소속과 과거 이력을 사용자 언어로 정리 |
| 조편성 진단 | issue가 있을 때만 노출 |
| 휴지통 | 복구 대상 조 선택 UX 개선 |
| 출석 snapshot | 충돌 해결과 명단 편집 UI 단순화 |
| SmartBatch | 분석/연동/조배정/저장 단계를 분리 |

## Cutover Decision

운영 1차는 “person source-of-truth + legacy compatibility”로 간다.

- `people`, `member_profiles`, `memberships`를 실제 사람/소속 기준으로 사용한다.
- `member_directory`, `group_members`는 기존 앱/출석/기도/리포트 호환을 위해 유지한다.
- 출석/기도 legacy FK 제거는 Phase 4에서 별도 설계한다.
