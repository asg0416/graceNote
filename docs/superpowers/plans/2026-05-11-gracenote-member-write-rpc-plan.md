# GraceNote Member Write RPC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move member add/edit writes behind a person-centered RPC while keeping legacy `member_directory` compatibility records during rollout.

**Architecture:** Add one DB RPC that accepts the current member form payload, resolves/creates `people`, writes/updates the compatibility `member_directory` row, and lets existing triggers maintain `member_profiles` and `memberships`. Then switch admin-web and Flutter member add/edit paths to call the RPC instead of direct `member_directory` writes. Guard and summary SQL remain rollout gates.

**Tech Stack:** Supabase Postgres migrations, Next.js admin-web Supabase client, Flutter Supabase client, targeted ESLint/Dart analyze, Phase 2/3 verification SQL.

---

## Scope

This plan covers only single/bulk member add/edit writes.

It does not cover regrouping source-of-truth conversion yet. Regrouping still uses `regroup_members` and is protected by post-write Phase 2 sync guards until the next RPC batch.

## Files

- Create: `supabase/migrations/20260511000000_phase3_member_write_rpc.sql`
  - Defines `public.upsert_member_person_membership(...)`.
- Create: `admin-web/src/lib/memberWriteRpc.ts`
  - Small client wrapper for the RPC and response shape.
- Modify: `admin-web/src/components/MemberModal.tsx`
  - Use RPC for immediate add/edit.
- Modify: `admin-web/src/components/SmartBatchModal.tsx`
  - Use RPC sequentially for bulk rows and keep existing duplicate checks/UI.
- Modify: `lib/core/repositories/grace_note_repository.dart`
  - Use RPC in `addDirectoryMember()` and `updateDirectoryMember()`.
- Modify: `docs/superpowers/plans/2026-05-07-gracenote-person-structure-app-admin-migration-plan.md`
  - Record Phase 3 member write RPC status.

## Task 1: Add Member Write RPC

- [ ] Create migration `supabase/migrations/20260511000000_phase3_member_write_rpc.sql`.

RPC signature:

```sql
create or replace function public.upsert_member_person_membership(
  p_member_directory_id uuid default null,
  p_church_id uuid default null,
  p_department_id uuid default null,
  p_full_name text default null,
  p_phone text default null,
  p_group_name text default null,
  p_role_in_group text default 'member',
  p_family_name text default null,
  p_spouse_name text default null,
  p_children_info text default null,
  p_birth_date date default null,
  p_wedding_anniversary date default null,
  p_notes text default null,
  p_avatar_url text default null,
  p_profile_id uuid default null,
  p_person_id uuid default null,
  p_is_active boolean default true
) returns public.member_directory
```

Implementation rules:

- Normalize `p_phone` to digits only.
- Require `p_church_id`, `p_department_id`, and non-empty `p_full_name`.
- Reject `p_profile_id` if profile belongs to another church.
- Resolve person through `phase2_upsert_person(...)`.
- Insert/update `member_directory` compatibility row.
- Preserve existing triggers so `member_profiles` and `memberships` are still updated by DB.
- Return the saved `member_directory` row.
- Grant execute to `authenticated` and `service_role`.

## Task 2: Verify RPC On Dev

- [ ] Push/apply migration to dev only.
- [ ] Run:

```bash
supabase db query --linked -f supabase/verify_phase2_consistency_summary_dev_2026-05-10.sql -o table
supabase db query --linked -f supabase/verify_phase3_attendance_prayer_person_snapshot_dev_2026-05-09.sql -o table
```

Expected:

- Phase 2 summary issue counts are all `0`.
- Phase 3 issue counts are all `0`.

If Supabase temp role authentication is blocked, stop and report the exact CLI error. Do not switch prod.

## Task 3: Switch Admin-Web MemberModal

- [ ] Create `admin-web/src/lib/memberWriteRpc.ts`.
- [ ] Replace direct `member_directory.insert/update` in `MemberModal.tsx` with RPC wrapper.
- [ ] Keep `assertPhase2MemberDirectorySync(...)` after the RPC returns.
- [ ] Run:

```bash
cd admin-web
npm run lint -- src/lib/memberWriteRpc.ts src/components/MemberModal.tsx
```

Expected: 0 errors. Existing warnings outside these files are acceptable.

## Task 4: Switch Admin-Web SmartBatchModal

- [ ] Replace bulk `member_directory.upsert(...)` with sequential RPC calls.
- [ ] Keep existing duplicate/person-link UI behavior.
- [ ] Collect returned row IDs and run `assertPhase2MemberDirectorySync(...)`.
- [ ] Run:

```bash
cd admin-web
npm run lint -- src/lib/memberWriteRpc.ts src/components/SmartBatchModal.tsx
```

Expected: 0 errors.

## Task 5: Switch Flutter Member Add/Edit

- [ ] Add private helper `_upsertMemberPersonMembership(...)` in `GraceNoteRepository`.
- [ ] Use it from `addDirectoryMember()` and `updateDirectoryMember()`.
- [ ] Keep direct inactive toggles unchanged for this batch; they are already guarded and will move in the next member lifecycle RPC batch.
- [ ] Run:

```bash
HOME=/private/tmp DART_SUPPRESS_ANALYTICS=true dart analyze lib/core/repositories/grace_note_repository.dart
```

Expected: no errors; existing style-only infos acceptable.

## Task 6: Final Verification And Commit

- [ ] Run `git diff --check`.
- [ ] Run secret scan:

```bash
rg -n "sbp_|gracenotejedi|postgresql://postgres|SUPABASE_SERVICE_ROLE_KEY=.*[A-Za-z0-9]" \
  supabase/migrations/20260511000000_phase3_member_write_rpc.sql \
  admin-web/src/lib/memberWriteRpc.ts \
  admin-web/src/components/MemberModal.tsx \
  admin-web/src/components/SmartBatchModal.tsx \
  lib/core/repositories/grace_note_repository.dart \
  docs/superpowers/plans/2026-05-07-gracenote-person-structure-app-admin-migration-plan.md
```

Expected: no matches.

- [ ] Commit:

```bash
git add supabase/migrations/20260511000000_phase3_member_write_rpc.sql \
  admin-web/src/lib/memberWriteRpc.ts \
  admin-web/src/components/MemberModal.tsx \
  admin-web/src/components/SmartBatchModal.tsx \
  lib/core/repositories/grace_note_repository.dart \
  docs/superpowers/plans/2026-05-07-gracenote-person-structure-app-admin-migration-plan.md
git commit -m "phase3: route member writes through person rpc"
```

## Smoke After Implementation

User smoke can happen after the commit:

- Admin-web single member add.
- Admin-web member edit.
- SmartBatch add existing same-church person to another department/group.
- SmartBatch new person add.
- Flutter admin member add/edit if the UI path is available.
- Run Phase 2 diagnostic panels and confirm issue count stays 0.

## Self-Review

- No prod DB steps are included.
- Regrouping source-of-truth conversion is explicitly deferred.
- Legacy tables remain compatibility records in this batch.
- The RPC centralizes member writes without breaking existing attendance/prayer FK assumptions.
