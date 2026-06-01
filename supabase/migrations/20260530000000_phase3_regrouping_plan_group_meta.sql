-- Persist group metadata in regrouping season plans.
-- Live groups already have these columns, but season drafts need the same metadata
-- so 새가족 조/등반 기준 survives draft save and reload.

alter table public.regrouping_plan_groups
  add column if not exists is_new_member_group boolean not null default false,
  add column if not exists climbing_threshold integer;

update public.regrouping_plan_groups rpg
set
  is_new_member_group = coalesce(g.is_new_member_group, false),
  climbing_threshold = case
    when coalesce(g.is_new_member_group, false) then g.climbing_threshold
    else null
  end
from public.groups g
where rpg.source_group_id = g.id
  and (
    rpg.is_new_member_group is distinct from coalesce(g.is_new_member_group, false)
    or rpg.climbing_threshold is distinct from case
      when coalesce(g.is_new_member_group, false) then g.climbing_threshold
      else null
    end
  );
