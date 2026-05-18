# GraceNote Dev DB Drift Log

> Purpose: 개발 서버에 직접 SQL을 적용하면서 `supabase_migrations.schema_migrations` 기록과 실제 스키마가 달라진 부분을 운영 반영 전에 추적하기 위한 문서다.

## 운영 원칙

- 운영 DB는 dev DB 상태를 복사하지 않는다.
- 운영 적용 기준은 `supabase/migrations/*.sql` 파일과 prod-safe verification SQL이다.
- dev에 직접 적용된 SQL은 “검증 흔적”이지 운영 적용 근거가 아니다.
- 앞으로 직접 SQL을 실행하면 이 문서에 즉시 남긴다.

## 현재 확인 시각

- 확인일: 2026-05-03
- 대상: 개발 Supabase `eftdfxmdiefdduksdpwg`
- 운영 Supabase `eejqiddsdovrabcsxznu`에는 이 문서의 작업을 적용하지 않았다.

## Migration History 상태

개발 DB의 `supabase_migrations.schema_migrations`는 현재 `20260501003000`까지만 기록되어 있다.

로컬에는 그 이후 migration 파일이 존재한다.

| Local Migration | Dev History | 상태 |
| --- | --- | --- |
| `20260502000000_phase2_member_directory_delete_sync.sql` | 없음 | dev 실제 적용됨으로 검증했으나 history 미기록 |
| `20260503000000_phase2_identifier_phone_update_sync.sql` | 없음 | dev 실제 적용됨으로 검증했으나 history 미기록 |
| `20260503001000_phase2_profile_identifier_relink_sync.sql` | 없음 | dev 실제 적용됨으로 검증했으나 history 미기록 |
| `20260503002000_phase2_group_delete_sync.sql` | 없음 | dev 실제 적용됨으로 검증했으나 history 미기록 |
| `20260503003000_phase2_department_delete_sync.sql` | 없음 | dev 실제 적용됨으로 검증했으나 history 미기록 |
| `20260503004000_phase2_group_delete_department_cascade_fix.sql` | 없음 | dev 실제 적용됨으로 검증했으나 history 미기록 |
| `20260503005000_p0_hard_delete_guardrails.sql` | 없음 | dev 직접 적용 완료. history 미기록 |
| `20260504000000_p0_member_directory_inactive_sync_fix.sql` | 없음 | dev 직접 적용 완료. history 미기록 |
| `20260504001000_p0_member_directory_assignment_scope_fix.sql` | 없음 | dev 직접 적용 완료. history 미기록 |
| `20260504002000_phase2_church_scoped_identity_guardrails.sql` | 없음 | dev 직접 적용 완료. history 미기록 |

## P0 직접 적용 상태

사용자 승인 후 dev DB에 처음 아래 SQL 1개가 직접 적용됐다.

```sql
alter table public.departments
  add column if not exists is_active boolean default true,
  add column if not exists ended_at timestamp with time zone;
```

이후 `20260503005000_p0_hard_delete_guardrails.sql`의 나머지 object도 migration 파일 기준으로 한 문장씩 직접 적용했다.

2026-05-04에 조 종료 실패 원인을 확인해 `handle_group_soft_end()`, `handle_department_soft_end()`를 다시 적용했다. 원인은 P0 함수가 `memberships.ended_at`을 참조했지만 실제 Phase 2 schema의 컬럼명은 `memberships.ends_at`인 오타였다. 로컬 migration 파일도 같은 기준으로 수정했다.

2026-05-04에 성도 비활성화 후 Phase 2 목록 진단 issue 1이 발생했다. 원인은 `member_directory.is_active=false`가 linked `group_members`/`memberships`까지 종료하지 않아 비활성 명부에 active membership이 남은 것이다. `phase2_sync_member_directory()`를 `20260504000000_p0_member_directory_inactive_sync_fix.sql` 기준으로 직접 재적용했다.

2026-05-04에 조편성에서 기존 성도 2명을 이동한 뒤 legacy 111 / Phase 2 110 누락이 발생했다. 원인은 inactive `member_directory` row가 기존 `group_name`을 계속 들고 있어 `member_directory_unique_assignment`의 자리를 잡고 있었기 때문이다. `20260504001000_p0_member_directory_assignment_scope_fix.sql`을 dev에 직접 적용했고, 기존 inactive row 5건의 `group_name`을 비웠다. 같은 migration에서 `check_phone_uniqueness()`도 같은 교회 active 성도 기준으로만 중복을 차단하도록 조정했다. 운영에는 이 직접 적용 기록이 아니라 migration 파일 기준으로 적용한다.

2026-05-04에 한 교회 성도 row가 다른 교회 `profiles.id`를 가리키면서 다른 교회 기도제목이 상세에 노출되는 문제가 확인됐다. 원인은 legacy `person_id`/profile sync 함수가 교회 범위를 충분히 강제하지 않았고, `member_directory.profile_id`가 다른 교회 `profiles.id`를 가리키는 것을 막는 DB trigger가 없었기 때문이다. `20260504002000_phase2_church_scoped_identity_guardrails.sql`을 dev에 직접 적용했고, 기존 cross-church profile link 1건을 `profile_id=null`, `is_linked=false`로 정리했다. 운영에는 migration 파일 기준으로 적용한다.

최종 적용 결과:

| Object | Dev Actual |
| --- | --- |
| `departments.is_active` | 존재, not null, default true |
| `departments.ended_at` | 존재 |
| `groups.is_active` | 존재, not null, default true |
| `groups.ended_at` | 존재 |
| `handle_group_soft_end()` | 존재 |
| `handle_department_soft_end()` | 존재 |
| `before_group_soft_end` trigger | 존재 |
| `before_department_soft_end` trigger | 존재 |
| `idx_departments_active_church` | 존재 |
| `idx_groups_active_department` | 존재 |
| `release_inactive_member_directory_assignment()` | 존재 |
| `before_member_directory_inactive_assignment_release` trigger | 존재 |
| `check_phone_uniqueness()` | 같은 교회 active 성도 기준으로 재정의 |
| `get_or_create_person_id(full_name, phone, church_id)` | 같은 교회 기준으로만 기존 person 재사용 |
| `before_member_directory_profile_same_church` trigger | 존재 |
| legacy profile/person sync 함수 | 같은 교회 범위로 제한 |

해석:

- dev에는 P0 object가 실제 적용되어 있다.
- 하지만 `supabase_migrations.schema_migrations`에는 `20260503005000`이 기록되지 않았다.
- 운영에서는 이 직접 적용 기록이 아니라 `20260503005000_p0_hard_delete_guardrails.sql` 파일을 처음부터 적용한다.

## P0 Dev Verification

| Check | Result |
| --- | --- |
| P0 columns/functions/triggers/indexes 존재 | 통과 |
| 조 soft-end 후 해당 조 active membership | 0 |
| 부서 soft-end 후 해당 부서 active membership | 0 |
| 주차 soft-disable | `weeks.is_active=false` update 확인 |
| P0 검증용 임시 데이터 cleanup | 0 rows remaining |
| 조 종료 trigger regression | `groups.is_active=false`, `groups.ended_at` set |
| inactive member sync regression | 비활성 `member_directory` 중 active membership 보유 row 0 |
| inactive assignment release regression | inactive row가 active assignment unique 자리를 막지 않음 |
| cross-church phone scope regression | 다른 교회 같은 전화번호는 허용, 같은 교회 active 중복은 차단 |
| church-scoped identity regression | 다른 교회 같은 이름/전화번호는 person_id 병합 안 됨, 다른 교회 profile link 차단 |

주의:

- `supabase db query --file`은 여러 SQL 문장을 prepared statement 하나로 처리하지 못해 `verify_p0_hard_delete_guardrails_dev_2026-05-03.sql` 전체 실행에는 부적합했다.
- dev 검증은 object 확인 쿼리와 분리된 insert/update/cleanup 쿼리로 수행했다.

## 앞으로의 진행 방식

1. DB 변경은 migration 파일을 원본으로 둔다.
2. dev 직접 SQL은 최소화한다.
3. dev에 직접 적용해야 하면 이 문서에 SQL, 목적, 결과를 남긴다.
4. 운영 반영 전에는 migration 파일 순서와 prod-safe verification SQL을 기준으로 다시 검증한다.
5. dev migration history drift는 운영 반영 blocker가 아니다. 단, dev에서 `db push`를 무작정 실행하면 충돌할 수 있으므로 금지한다.

## 즉시 주의할 점

- `supabase db push`로 dev에 누락 migration을 한 번에 밀지 않는다.
- `20260502/20260503` migration들이 dev 실제 스키마에 적용되어 있는지 개별 verification SQL로 확인한다.
- 운영 반영 전에는 dev history가 아니라 fresh prod schema 기준으로 적용 순서를 검증한다.
