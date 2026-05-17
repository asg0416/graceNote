-- Prevent maintenance/backfill updates on already-published prayer entries from
-- re-triggering push notifications. A prayer notification should fire on a new
-- published insert or on the transition into published, not on metadata repairs.
create or replace function public.notify_on_event()
returns trigger
language plpgsql
security definer
as $function$
declare
  _payload jsonb;
  _url text;
begin
  if tg_table_name = 'prayer_entries' then
    if tg_op = 'INSERT' and coalesce(new.status, '') <> 'published' then
      return new;
    end if;

    if tg_op = 'UPDATE' and not (
      coalesce(old.status, '') is distinct from coalesce(new.status, '')
      and coalesce(new.status, '') = 'published'
    ) then
      return new;
    end if;
  end if;

  select value into _url from public.app_config where key = 'edge_function_base_url';
  if _url is null then
    raise warning 'edge_function_base_url not configured in app_config';
    return new;
  end if;

  _payload := jsonb_build_object(
    'type', tg_op,
    'table', tg_table_name,
    'record', row_to_json(new)::jsonb,
    'schema', tg_table_schema,
    'old_record', case when tg_op = 'UPDATE' then row_to_json(old)::jsonb else null end
  );

  perform net.http_post(url := _url || '/notify-event', body := _payload);
  return new;
exception
  when others then
    raise warning 'Push notification trigger failed: %', sqlerrm;
    return new;
end;
$function$;
