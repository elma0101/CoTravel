create table public.trips (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  origin_city text not null,
  destination_city text not null,
  start_date date not null,
  end_date date not null,
  capacity smallint not null,
  confirmed_traveler_count smallint not null default 0,
  open_seats smallint generated always as (
    capacity - 1 - confirmed_traveler_count
  ) stored,
  lodging_total numeric(12, 2) not null,
  transport_total numeric(12, 2) not null,
  currency text not null default 'MAD',
  travel_style text not null,
  summary text not null,
  status text not null default 'published',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trips_title_length check (char_length(title) between 4 and 80),
  constraint trips_city_lengths check (
    char_length(origin_city) between 2 and 80
    and char_length(destination_city) between 2 and 80
  ),
  constraint trips_dates_valid check (end_date >= start_date),
  constraint trips_capacity_range check (capacity between 2 and 12),
  constraint trips_confirmed_count_valid check (
    confirmed_traveler_count between 0 and capacity - 1
  ),
  constraint trips_costs_valid check (
    lodging_total >= 0
    and transport_total >= 0
    and lodging_total + transport_total > 0
  ),
  constraint trips_currency_format check (currency ~ '^[A-Z]{3}$'),
  constraint trips_style_length check (char_length(travel_style) between 2 and 40),
  constraint trips_summary_length check (char_length(summary) between 20 and 600),
  constraint trips_status_valid check (
    status in ('draft', 'published', 'closed', 'cancelled')
  )
);

create table public.trip_stops (
  id bigint generated always as identity primary key,
  trip_id uuid not null references public.trips (id) on delete cascade,
  position smallint not null,
  city text not null,
  arrival_date date not null,
  notes text,
  created_at timestamptz not null default now(),
  constraint trip_stops_position_positive check (position > 0),
  constraint trip_stops_city_length check (char_length(city) between 2 and 80),
  constraint trip_stops_notes_length check (
    notes is null or char_length(notes) <= 240
  ),
  constraint trip_stops_unique_position unique (trip_id, position)
);

create index trips_discovery_start_date_idx
on public.trips (status, start_date)
where status = 'published';

create index trips_destination_lower_idx
on public.trips (lower(destination_city));

create index trips_host_id_idx on public.trips (host_id);
create index trip_stops_trip_id_idx on public.trip_stops (trip_id, position);

create trigger trips_set_updated_at
before update on public.trips
for each row execute function public.set_updated_at();

alter table public.trips enable row level security;
alter table public.trip_stops enable row level security;

grant select on public.trips to authenticated;
grant select on public.trip_stops to authenticated;

create policy "Authenticated users can discover published trips"
on public.trips
for select
to authenticated
using (
  status = 'published'
  or host_id = (select auth.uid())
);

create policy "Authenticated users can read visible trip stops"
on public.trip_stops
for select
to authenticated
using (
  exists (
    select 1
    from public.trips
    where trips.id = trip_stops.trip_id
      and (
        trips.status = 'published'
        or trips.host_id = (select auth.uid())
      )
  )
);

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
  ) then
    raise exception 'Every stop must contain a valid city and trip date';
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
    notes
  )
  select
    created_trip_id,
    stop.ordinality::smallint,
    trim(stop.value ->> 'city'),
    (stop.value ->> 'arrival_date')::date,
    nullif(trim(stop.value ->> 'notes'), '')
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
