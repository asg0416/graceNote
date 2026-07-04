-- Prevent season-plan group ids from being stored in previous_source_group_id.
-- previous_source_group_id references public.groups(id); new season draft groups
-- live in regrouping_plan_groups and must not be treated as source groups.

set check_function_bodies = off;

create or replace function public.sanitize_regrouping_plan_assignment_previous_source_group_id()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.previous_source_group_id is not null
    and not exists (
      select 1
      from public.groups g
      where g.id = new.previous_source_group_id
    )
  then
    new.previous_source_group_id := null;
  end if;

  return new;
end;
$$;

drop trigger if exists sanitize_regrouping_plan_assignment_previous_source_group_id
on public.regrouping_plan_assignments;

create trigger sanitize_regrouping_plan_assignment_previous_source_group_id
before insert or update of previous_source_group_id
on public.regrouping_plan_assignments
for each row
execute function public.sanitize_regrouping_plan_assignment_previous_source_group_id();
