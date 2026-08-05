create table public.trip_logistics (
  trip_id uuid primary key references public.trips (id) on delete cascade,
  accommodation_name text,
  accommodation_url text,
  transport_name text,
  transport_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trip_logistics_accommodation_name_length check (
    accommodation_name is null
    or char_length(accommodation_name) between 2 and 100
  ),
  constraint trip_logistics_transport_name_length check (
    transport_name is null
    or char_length(transport_name) between 2 and 100
  ),
  constraint trip_logistics_accommodation_url_valid check (
    accommodation_url is null
    or (
      char_length(accommodation_url) <= 500
      and accommodation_url ~* '^https?://'
    )
  ),
  constraint trip_logistics_transport_url_valid check (
    transport_url is null
    or (
      char_length(transport_url) <= 500
      and transport_url ~* '^https?://'
    )
  ),
  constraint trip_logistics_notes_length check (
    notes is null or char_length(notes) <= 600
  )
);

create trigger trip_logistics_set_updated_at
before update on public.trip_logistics
for each row execute function public.set_updated_at();

alter table public.trip_logistics enable row level security;

grant select on public.trip_logistics to authenticated;

create or replace function public.is_confirmed_trip_member(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trips
    where id = p_trip_id
      and host_id = (select auth.uid())
  ) or exists (
    select 1
    from public.trip_join_requests
    where trip_id = p_trip_id
      and traveler_id = (select auth.uid())
      and status = 'confirmed'
  );
$$;

revoke all on function public.is_confirmed_trip_member(uuid) from public;
grant execute on function public.is_confirmed_trip_member(uuid) to authenticated;

create policy "Confirmed trip members can read logistics"
on public.trip_logistics
for select
to authenticated
using (public.is_confirmed_trip_member(trip_id));

create or replace function public.save_trip_logistics(
  p_trip_id uuid,
  p_lodging_total numeric,
  p_transport_total numeric,
  p_accommodation_name text,
  p_accommodation_url text,
  p_transport_name text,
  p_transport_url text,
  p_notes text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_trip public.trips;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select *
  into target_trip
  from public.trips
  where id = p_trip_id
  for update;

  if target_trip.id is null then
    raise exception 'Trip not found';
  end if;

  if target_trip.host_id <> (select auth.uid()) then
    raise exception 'Only this trip host can update logistics';
  end if;

  if p_lodging_total < 0
    or p_transport_total < 0
    or p_lodging_total + p_transport_total <= 0 then
    raise exception 'Add a valid lodging or transport estimate';
  end if;

  if char_length(coalesce(trim(p_accommodation_name), '')) > 100
    or char_length(coalesce(trim(p_transport_name), '')) > 100 then
    raise exception 'Booking link labels must contain at most 100 characters';
  end if;

  if (p_accommodation_url is not null and (
      char_length(trim(p_accommodation_url)) > 500
      or trim(p_accommodation_url) !~* '^https?://'
    ))
    or (p_transport_url is not null and (
      char_length(trim(p_transport_url)) > 500
      or trim(p_transport_url) !~* '^https?://'
    )) then
    raise exception 'Booking links must be valid HTTP or HTTPS URLs';
  end if;

  if char_length(coalesce(trim(p_notes), '')) > 600 then
    raise exception 'Logistics notes must contain at most 600 characters';
  end if;

  update public.trips
  set lodging_total = p_lodging_total,
      transport_total = p_transport_total
  where id = p_trip_id;

  insert into public.trip_logistics (
    trip_id,
    accommodation_name,
    accommodation_url,
    transport_name,
    transport_url,
    notes
  )
  values (
    p_trip_id,
    nullif(trim(p_accommodation_name), ''),
    nullif(trim(p_accommodation_url), ''),
    nullif(trim(p_transport_name), ''),
    nullif(trim(p_transport_url), ''),
    nullif(trim(p_notes), '')
  )
  on conflict (trip_id) do update
  set accommodation_name = excluded.accommodation_name,
      accommodation_url = excluded.accommodation_url,
      transport_name = excluded.transport_name,
      transport_url = excluded.transport_url,
      notes = excluded.notes;

  return p_trip_id;
end;
$$;

revoke all on function public.save_trip_logistics(
  uuid,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  text
) from public;
grant execute on function public.save_trip_logistics(
  uuid,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  text
) to authenticated;
