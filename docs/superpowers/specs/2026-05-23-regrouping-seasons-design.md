# GraceNote Regrouping Seasons Design

Date: 2026-05-23
Status: Draft for implementation

## Context

GraceNote has moved member identity and membership reads toward the Phase 2 person structure:

- `people` is the real person identity.
- `member_profiles` links legacy member rows and app profiles to a person.
- `memberships` is the person-based church/department/group membership history.
- `member_directory` and `group_members` still exist as compatibility tables.
- `attendance` and `prayer_entries` still keep legacy FK compatibility for now.

The current regrouping work added an `effective_week_date` overload to `save_regrouping_memberships`. That is useful for current or past backfill correction, but it is not the final product model for future regrouping.

The target user workflow is different:

- A church admin may prepare a future quarter or semester regrouping in advance.
- The future arrangement must not appear in Flutter prayer/attendance tabs before the effective week.
- Past prayer and attendance records must keep the group name that was true at the time of the record.
- Admins need a safe draft/edit/confirm flow rather than directly changing live groups every time they drag cards.

Therefore future regrouping must be modeled as a planned season/draft first, then applied to live memberships in a controlled transition.

## Problem With The Current 1st-Stage Effective Week UI

The current `effectiveWeekDate` save path still calls the live regrouping RPC. That means it directly changes live compatibility rows and then adjusts group/membership periods afterward.

This is acceptable for:

- Backfilling a regrouping that already took effect in the field.
- Correcting a current arrangement.
- Migration/repair workflows.

It is not acceptable for:

- Preparing a July regrouping in May.
- Letting admins edit a future arrangement over several days.
- Showing a preview without changing what members and leaders see in the app.

Because of that, continuing to smoke-test the temporary UI as if it were the final UX will produce misleading feedback. The final feature should be tested after the season/draft structure exists.

## Product Model

Regrouping becomes a three-layer model.

1. Live membership

This is the currently effective state used by the app and admin operational screens.

- `groups`
- `member_directory`
- `group_members`
- `memberships`

2. Planned regrouping season

This is an admin-created plan such as `2026 Q3 Olive Couples`.

- It belongs to one church and one department.
- It has an `effective_week_date`.
- It can be edited while in draft state.
- It can be confirmed/applied once.

3. Planned groups and assignments

These are the future cards and placements inside the plan.

- Planned groups may map to existing groups or represent new groups.
- Planned assignments map people to planned groups.
- They should reference `person_id` as the primary identity.
- Legacy row ids are optional compatibility hints, not the source of truth.

## Proposed Tables

### `regrouping_seasons`

Purpose: One regrouping plan for a church department and effective week.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `church_id uuid not null references churches(id)`
- `department_id uuid not null references departments(id)`
- `title text not null`
- `status text not null default 'draft'`
- `effective_week_date date not null`
- `created_by uuid references profiles(id)`
- `applied_by uuid references profiles(id)`
- `applied_at timestamptz`
- `created_at timestamptz default now()`
- `updated_at timestamptz default now()`

Status values:

- `draft`: editable and not visible to normal app screens.
- `ready`: reviewed by admin, still not live.
- `applied`: already transitioned to live memberships.
- `archived`: kept for history but not editable.
- `cancelled`: abandoned plan.

Important constraints:

- One department should not have two non-cancelled seasons with the same `effective_week_date`.
- `applied_at` must be present only when status is `applied`.

Suggested indexes:

- `(church_id, department_id, status)`
- `(church_id, department_id, effective_week_date)`

### `regrouping_plan_groups`

Purpose: Group cards inside a season.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `season_id uuid not null references regrouping_seasons(id) on delete cascade`
- `source_group_id uuid references groups(id)`
- `name text not null`
- `color_hex text`
- `sort_order integer not null default 0`
- `leader_person_id uuid references people(id)`
- `created_at timestamptz default now()`
- `updated_at timestamptz default now()`

Meaning:

- `source_group_id` exists when this planned group is a continuation/rename of an existing group.
- `source_group_id` is null when this planned group is newly created by the season.
- `leader_person_id` is a person-based leader hint; final live compatibility rows are created at apply time.

Suggested indexes:

- `(season_id, sort_order)`
- `(season_id, source_group_id)`

### `regrouping_plan_assignments`

Purpose: Person placements inside planned groups.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `season_id uuid not null references regrouping_seasons(id) on delete cascade`
- `plan_group_id uuid references regrouping_plan_groups(id) on delete cascade`
- `person_id uuid not null references people(id)`
- `role_in_group text not null default 'member'`
- `sort_order integer not null default 0`
- `source_membership_id uuid references memberships(id)`
- `source_member_directory_id uuid references member_directory(id)`
- `created_at timestamptz default now()`
- `updated_at timestamptz default now()`

Meaning:

- `person_id` is authoritative.
- `plan_group_id` can be null for a planned unassigned person.
- `source_membership_id` and `source_member_directory_id` help compatibility and audit, but are not the identity.

Important constraints:

- Prevent duplicate `(season_id, plan_group_id, person_id)` rows.
- Allow a person to be in multiple planned groups only when the department policy allows multi-group membership.
- For couple departments, spouse movement is a UI rule, not a database auto-merge rule.

Suggested indexes:

- `(season_id, person_id)`
- `(season_id, plan_group_id, sort_order)`

## RPC/API Design

### `create_regrouping_season`

Creates a season for a church department.

Inputs:

- `church_id`
- `department_id`
- `title`
- `effective_week_date`

Output:

- `season_id`

Rules:

- User must be an approved admin/master for the church.
- Effective week should snap to Sunday in the client and be validated in DB.
- Creating a season does not change live `groups` or `memberships`.

### `save_regrouping_season_draft`

Saves planned groups and assignments for a season.

Inputs:

- `season_id`
- `groups jsonb`
- `assignments jsonb`

Output:

- saved counts or normalized rows

Rules:

- Only `draft` or `ready` seasons are editable.
- Writes only `regrouping_plan_groups` and `regrouping_plan_assignments`.
- Does not write live `groups`, `member_directory`, `group_members`, or `memberships`.
- Uses `person_id` as the primary assignment identity.

### `apply_regrouping_season`

Transitions a season to live state.

Inputs:

- `season_id`

Output:

- created/ended group counts
- created/ended membership counts
- affected person count

Rules:

- Runs in one transaction.
- Validates the season is not already applied.
- Ends live memberships for that department at `effective_week_date - 1 second`.
- Creates or updates live groups with `active_from = effective_week_date`.
- Creates person-based active `memberships` from assignments.
- Writes legacy compatibility rows as needed for attendance/prayer compatibility.
- Marks season `applied`.
- Can be safely retried only if no partial apply happened; otherwise it must fail with a clear error.

The existing 4-arg and 5-arg `save_regrouping_memberships` RPCs remain for current/past correction and compatibility, but future season apply should eventually use `apply_regrouping_season`.

## Admin Web UX

### Department regrouping landing

Instead of one live-editing screen only, the admin sees season context:

- Current live arrangement
- Draft/ready future seasons
- Applied season history

Primary actions:

- `새 조편성 계획 만들기`
- `현재 조편성 수정`
- `과거 적용 주차 보정`

### Create season flow

Fields:

- Title, e.g. `2026년 3분기 조편성`
- Effective week date
- Optional base source:
  - current live arrangement
  - previous season
  - empty plan

### Draft editor

The editor can reuse most of the current drag-and-drop UI, but its save target changes:

- Save draft writes plan tables only.
- No Flutter app user sees the draft.
- Existing `적용 주차` becomes a season property, not an ad-hoc save option.
- The page clearly shows `초안`, `검토 완료`, or `적용 완료`.

### Apply confirmation

Applying a season should show a confirmation summary:

- Effective week
- New groups
- Ended groups
- People moved
- People unassigned
- Duplicate/multi-group warnings

After confirmation, run `apply_regrouping_season`.

## Flutter/Admin Read Rules

Normal operational screens should not query draft tables.

### Before effective week

- Flutter prayer tabs show live groups active for the selected week.
- Flutter attendance shows live groups active for the selected week.
- Admin attendance shows live/snapshot groups for the selected week.
- Future draft groups are hidden.

### From effective week onward after apply

- New groups appear because they are now live groups with `active_from`.
- Ended groups disappear from default tabs after `ended_at`, unless the selected week has actual prayer/attendance records for them.

### Historical records

Past prayer and attendance cards must use recorded group identity:

- `prayer_entries.recorded_group_id`
- `attendance.group_id` or snapshot group data
- `attendance_roster_snapshot_members`

Never re-label historical records using a person's current group.

## Performance And Load

The season model should not create meaningful DB load if draft and live reads stay separated.

Principles:

- Flutter app and normal admin operational screens read live `groups/memberships`, not draft tables.
- Draft tables are read only on the admin regrouping editor.
- Draft save should be debounced or explicit-save based.
- Applying a season is one transaction, not many client-side writes.
- Old draft seasons can be archived and excluded from default queries.

Expected row volume is small compared with attendance logs:

- 300 people x 2 seasons/year x 100 churches = about 60,000 plan assignment rows/year.
- This is small for Postgres with proper `(season_id, person_id)` and `(season_id, plan_group_id)` indexes.

## Data Integrity Rules

- Person identity is always `person_id`.
- `member_directory.id` is compatibility, not identity.
- Historical prayer/attendance display uses recorded group/snapshot identity.
- Draft changes must not mutate live rows.
- Apply must be transactionally all-or-nothing.
- Manual data repair and automatic season application must be separate code paths.

## Migration Strategy

1. Keep the current `effective_week_date` RPC as compatibility for current/past correction.
2. Add season/draft tables additively.
3. Build draft save/read without changing live regrouping behavior.
4. Add apply RPC behind feature flag or admin-only UI.
5. Convert the regrouping page to season-first UX.
6. Verify Flutter prayer/attendance tabs with selected weeks before and after apply.
7. Keep legacy compatibility rows until attendance/prayer FK migration is done in a later phase.

## Smoke Scenarios

### Future season does not leak

1. Create a future season for an upcoming week.
2. Add a new group and assign members.
3. Save draft.
4. Confirm Flutter prayer tabs and attendance tabs before the effective week do not show the new group.
5. Confirm admin attendance before the effective week does not show the new group unless there is actual historical data.

### Apply season

1. Apply the season.
2. Select a week before `effective_week_date`.
3. Old groups should still be visible where active or historically recorded.
4. Select the effective week.
5. New groups should appear.
6. Ended groups should disappear from default tabs unless records exist for that week.

### Historical prayer names

1. Create a prayer entry in an old group.
2. Apply a future season that moves the person to a new group.
3. Open the old prayer week.
4. The card should show the old group name.
5. Open a new prayer week after apply.
6. New entries should show the new group name.

### Attendance snapshots

1. Open an old attendance week.
2. Confirm roster snapshot/group display uses that week's snapshot or historical group period.
3. Apply a new season.
4. Old attendance week should not be relabeled to the new group.

## Non-Goals

- This design does not remove `member_directory` or `group_members`.
- This design does not remove legacy FK from `attendance` or `prayer_entries`.
- This design does not implement fully automatic seasonal recurrence.
- This design does not auto-merge same-name or same-phone people.

## Open Implementation Notes

- The existing `effective_week_date` UI should either be hidden behind an advanced correction mode or replaced by season selection in the final regrouping page.
- The exact department policy for multi-group membership should be read from existing department type/settings where possible.
- Couple movement should remain an editor convenience when spouses are in the same source group, not a DB-level rule that pulls spouses across unrelated groups.
- A future cleanup phase should archive stale drafts and expose applied season history in a compact UI.
