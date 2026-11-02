-- What a traveler declares when asking to join, shown to the host as context.
-- Null means the request predates these questions. None of this is checked.
alter table public.trip_join_requests
  add column available_all_dates boolean,
  add column budget_fits boolean,
  add column can_share_driving boolean;

create or replace function public.create_join_request(
  p_trip_id uuid,
  p_message text,
  p_available_all_dates boolean,
  p_budget_fits boolean,
  p_can_share_driving boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id uuid;
begin
  -- The two-argument function keeps every eligibility rule in one place.
  v_request_id := public.create_join_request(p_trip_id, p_message);

  update public.trip_join_requests
  set available_all_dates = p_available_all_dates,
      budget_fits = p_budget_fits,
      can_share_driving = p_can_share_driving
  where id = v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.create_join_request(uuid, text, boolean, boolean, boolean)
from public, anon;
grant execute on function public.create_join_request(uuid, text, boolean, boolean, boolean)
to authenticated;
