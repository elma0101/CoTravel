-- The exact departure point, such as a station, when the host picks one from
-- the place suggestions. Trips without one fall back to the town on the map.
alter table public.trips
add column origin_latitude double precision,
add column origin_longitude double precision;

alter table public.trips
add constraint trips_origin_point_complete check (
  (origin_latitude is null and origin_longitude is null)
  or (
    origin_latitude between -90 and 90
    and origin_longitude between -180 and 180
  )
);

-- A renamed departure no longer matches its point, so the point is dropped
-- unless the same update sets a new one.
create or replace function public.clear_stale_trip_origin_point()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.origin_city is distinct from old.origin_city
    and new.origin_latitude is not distinct from old.origin_latitude
    and new.origin_longitude is not distinct from old.origin_longitude then
    new.origin_latitude := null;
    new.origin_longitude := null;
  end if;
  return new;
end;
$$;

revoke all on function public.clear_stale_trip_origin_point()
from public, anon, authenticated;

create trigger trips_clear_stale_origin_point
before update of origin_city on public.trips
for each row
execute function public.clear_stale_trip_origin_point();

create or replace function public.set_trip_origin_point(
  p_trip_id uuid,
  p_latitude double precision,
  p_longitude double precision
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.trips
    where id = p_trip_id
      and host_id = (select auth.uid())
  ) then
    raise exception 'Only this trip host can edit the trip';
  end if;

  if (p_latitude is null) <> (p_longitude is null)
    or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180 then
    raise exception 'Choose a valid departure point';
  end if;

  update public.trips
  set origin_latitude = p_latitude,
      origin_longitude = p_longitude
  where id = p_trip_id;
end;
$$;

revoke all on function public.set_trip_origin_point(
  uuid, double precision, double precision
) from public, anon;
grant execute on function public.set_trip_origin_point(
  uuid, double precision, double precision
) to authenticated;
