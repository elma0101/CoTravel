alter table public.trip_stops
add column latitude double precision,
add column longitude double precision,
add column stop_type text not null default 'waypoint',
add column travel_mode text,
add column travel_duration_minutes smallint,
add column is_optional boolean not null default false;

alter table public.trip_stops
add constraint trip_stops_coordinates_complete check (
  (latitude is null and longitude is null)
  or (
    latitude between -90 and 90
    and longitude between -180 and 180
  )
),
add constraint trip_stops_type_valid check (
  stop_type in ('waypoint', 'activity', 'overnight', 'break')
),
add constraint trip_stops_travel_mode_valid check (
  travel_mode is null
  or travel_mode in ('drive', 'shared_taxi', 'train', 'bus', 'walk', 'other')
),
add constraint trip_stops_travel_duration_valid check (
  travel_duration_minutes is null
  or travel_duration_minutes between 1 and 1440
);

create index trip_stops_coordinates_idx
on public.trip_stops (latitude, longitude)
where latitude is not null and longitude is not null;

create or replace function public.create_trip(
  p_title text,
  p_origin_city text,
  p_start_date date,
  p_end_date date,
  p_stops jsonb,
  p_capacity smallint,
  p_lodging_total numeric,
  p_transport_total numeric,
  p_currency text,
  p_travel_style text,
  p_summary text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_trip_id uuid;
  destination text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and onboarding_completed_at is not null
      and linkedin_verified_at is not null
  ) then
    raise exception 'A complete, verified profile is required to publish trips';
  end if;

  if char_length(trim(p_title)) not between 4 and 80 then
    raise exception 'Trip title must contain 4 to 80 characters';
  end if;

  if char_length(trim(p_origin_city)) not between 2 and 80 then
    raise exception 'Origin city must contain 2 to 80 characters';
  end if;

  if p_start_date < current_date or p_end_date < p_start_date then
    raise exception 'Choose a valid future date range';
  end if;

  if p_capacity not between 2 and 12 then
    raise exception 'Capacity must be between 2 and 12 people';
  end if;

  if p_lodging_total < 0
    or p_transport_total < 0
    or p_lodging_total + p_transport_total <= 0 then
    raise exception 'Add a valid lodging or transport estimate';
  end if;

  if upper(trim(p_currency)) !~ '^[A-Z]{3}$' then
    raise exception 'Currency must use a three-letter code';
  end if;

  if char_length(trim(p_travel_style)) not between 2 and 40 then
    raise exception 'Choose a travel style';
  end if;

  if char_length(trim(p_summary)) not between 20 and 600 then
    raise exception 'Trip summary must contain 20 to 600 characters';
  end if;

  if jsonb_typeof(p_stops) <> 'array'
    or jsonb_array_length(p_stops) not between 1 and 8 then
    raise exception 'Add between 1 and 8 route stops';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_stops) as stop
    where char_length(trim(stop ->> 'city')) not between 2 and 80
      or (stop ->> 'arrival_date')::date not between p_start_date and p_end_date
      or char_length(coalesce(stop ->> 'notes', '')) > 240
      or ((stop ->> 'latitude') is null) <> ((stop ->> 'longitude') is null)
      or (
        (stop ->> 'latitude') is not null
        and (stop ->> 'latitude')::double precision not between -90 and 90
      )
      or (
        (stop ->> 'longitude') is not null
        and (stop ->> 'longitude')::double precision not between -180 and 180
      )
      or coalesce(stop ->> 'stop_type', 'waypoint')
        not in ('waypoint', 'activity', 'overnight', 'break')
      or (
        (stop ->> 'travel_mode') is not null
        and (stop ->> 'travel_mode')
          not in ('drive', 'shared_taxi', 'train', 'bus', 'walk', 'other')
      )
      or (
        (stop ->> 'travel_duration_minutes') is not null
        and (stop ->> 'travel_duration_minutes')::integer not between 1 and 1440
      )
  ) then
    raise exception 'Every stop must contain valid route details';
  end if;

  destination := trim(
    p_stops -> (jsonb_array_length(p_stops) - 1) ->> 'city'
  );

  insert into public.trips (
    host_id,
    title,
    origin_city,
    destination_city,
    start_date,
    end_date,
    capacity,
    lodging_total,
    transport_total,
    currency,
    travel_style,
    summary
  )
  values (
    (select auth.uid()),
    trim(p_title),
    trim(p_origin_city),
    destination,
    p_start_date,
    p_end_date,
    p_capacity,
    p_lodging_total,
    p_transport_total,
    upper(trim(p_currency)),
    trim(p_travel_style),
    trim(p_summary)
  )
  returning id into created_trip_id;

  insert into public.trip_stops (
    trip_id,
    position,
    city,
    arrival_date,
    notes,
    latitude,
    longitude,
    stop_type,
    travel_mode,
    travel_duration_minutes,
    is_optional
  )
  select
    created_trip_id,
    stop.ordinality::smallint,
    trim(stop.value ->> 'city'),
    (stop.value ->> 'arrival_date')::date,
    nullif(trim(stop.value ->> 'notes'), ''),
    (stop.value ->> 'latitude')::double precision,
    (stop.value ->> 'longitude')::double precision,
    coalesce(stop.value ->> 'stop_type', 'waypoint'),
    nullif(stop.value ->> 'travel_mode', ''),
    (stop.value ->> 'travel_duration_minutes')::smallint,
    coalesce((stop.value ->> 'is_optional')::boolean, false)
  from jsonb_array_elements(p_stops) with ordinality as stop(value, ordinality);

  return created_trip_id;
end;
$$;

revoke all on function public.create_trip(
  text,
  text,
  date,
  date,
  jsonb,
  smallint,
  numeric,
  numeric,
  text,
  text,
  text
) from public;

grant execute on function public.create_trip(
  text,
  text,
  date,
  date,
  jsonb,
  smallint,
  numeric,
  numeric,
  text,
  text,
  text
) to authenticated;

comment on column public.trip_stops.latitude is
'Latitude used by the interactive trip route. Null keeps legacy text-only stops valid.';

comment on column public.trip_stops.travel_duration_minutes is
'Expected travel time from the previous itinerary point.';
