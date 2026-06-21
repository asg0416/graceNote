-- Allow multiple removed memberships for the same person in one season.
-- A person can be removed from several concurrent groups, while only one
-- real unassigned row should exist for the person.

drop index if exists public.regrouping_plan_assignments_unique_unassigned_person;

create unique index if not exists regrouping_plan_assignments_unique_unassigned_person
on public.regrouping_plan_assignments (season_id, person_id)
where plan_group_id is null
  and coalesce(change_type, '') <> 'removed';

create unique index if not exists regrouping_plan_assignments_unique_removed_membership
on public.regrouping_plan_assignments (season_id, person_id, source_membership_id)
where plan_group_id is null
  and change_type = 'removed'
  and source_membership_id is not null;

create unique index if not exists regrouping_plan_assignments_unique_removed_source_group
on public.regrouping_plan_assignments (season_id, person_id, previous_source_group_id)
where plan_group_id is null
  and change_type = 'removed'
  and source_membership_id is null
  and previous_source_group_id is not null;

update public.regrouping_plan_assignments rpa
set previous_group_name = g.name
from public.groups g
where rpa.change_type = 'removed'
  and rpa.plan_group_id is null
  and rpa.previous_source_group_id = g.id
  and rpa.previous_group_name = '추가 소속';
