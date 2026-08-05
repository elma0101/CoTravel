create table public.trip_join_requests (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  traveler_id uuid not null references public.profiles (id) on delete cascade,
  message text not null,
  status text not null default 'pending_host',
  host_decided_at timestamptz,
  traveler_decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trip_join_requests_message_length check (
    char_length(message) between 20 and 300
  ),
  constraint trip_join_requests_status_valid check (
    status in (
      'pending_host',
      'pending_traveler',
      'confirmed',
      'declined',
      'withdrawn'
    )
  )
);

create unique index trip_join_requests_one_active_request_idx
on public.trip_join_requests (trip_id, traveler_id)
where status in ('pending_host', 'pending_traveler', 'confirmed');

create index trip_join_requests_traveler_idx
on public.trip_join_requests (traveler_id, created_at desc);

create index trip_join_requests_trip_idx
on public.trip_join_requests (trip_id, created_at desc);

create trigger trip_join_requests_set_updated_at
before update on public.trip_join_requests
for each row execute function public.set_updated_at();

alter table public.trip_join_requests enable row level security;

grant select on public.trip_join_requests to authenticated;

create policy "Participants can read relevant join requests"
on public.trip_join_requests
for select
to authenticated
using (
  traveler_id = (select auth.uid())
  or exists (
    select 1
    from public.trips
    where trips.id = trip_join_requests.trip_id
      and trips.host_id = (select auth.uid())
  )
);

create or replace function public.create_join_request(
  p_trip_id uuid,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_trip public.trips;
  created_request_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if char_length(trim(p_message)) not between 20 and 300 then
    raise exception 'Join request must contain 20 to 300 characters';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and onboarding_completed_at is not null
      and linkedin_verified_at is not null
  ) then
    raise exception 'A complete, verified profile is required to join trips';
  end if;

  select *
  into target_trip
  from public.trips
  where id = p_trip_id
  for update;

  if target_trip.id is null or target_trip.status <> 'published' then
    raise exception 'This trip is not open for requests';
  end if;

  if target_trip.host_id = (select auth.uid()) then
    raise exception 'Hosts cannot request to join their own trip';
  end if;

  if target_trip.open_seats <= 0 then
    raise exception 'This trip has no open seats';
  end if;

  insert into public.trip_join_requests (
    trip_id,
    traveler_id,
    message
  )
  values (
    p_trip_id,
    (select auth.uid()),
    trim(p_message)
  )
  returning id into created_request_id;

  return created_request_id;
exception
  when unique_violation then
    raise exception 'You already have an active request for this trip';
end;
$$;

create or replace function public.review_join_request(
  p_request_id uuid,
  p_accept boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_record record;
  next_status text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select request.*, trip.host_id, trip.open_seats
  into request_record
  from public.trip_join_requests as request
  join public.trips as trip on trip.id = request.trip_id
  where request.id = p_request_id
  for update of request, trip;

  if request_record.id is null then
    raise exception 'Join request not found';
  end if;

  if request_record.host_id <> (select auth.uid()) then
    raise exception 'Only this trip host can review the request';
  end if;

  if request_record.status <> 'pending_host' then
    raise exception 'This request has already been reviewed';
  end if;

  if p_accept and request_record.open_seats <= 0 then
    raise exception 'This trip has no open seats';
  end if;

  next_status := case when p_accept then 'pending_traveler' else 'declined' end;

  update public.trip_join_requests
  set status = next_status,
      host_decided_at = now()
  where id = p_request_id;

  return next_status;
end;
$$;

create or replace function public.confirm_join_request(
  p_request_id uuid,
  p_confirm boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_record public.trip_join_requests;
  target_trip public.trips;
  next_status text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select *
  into request_record
  from public.trip_join_requests
  where id = p_request_id
  for update;

  if request_record.id is null then
    raise exception 'Join request not found';
  end if;

  if request_record.traveler_id <> (select auth.uid()) then
    raise exception 'Only this traveler can confirm the request';
  end if;

  if request_record.status <> 'pending_traveler' then
    raise exception 'This request is not awaiting traveler confirmation';
  end if;

  if not p_confirm then
    update public.trip_join_requests
    set status = 'withdrawn',
        traveler_decided_at = now()
    where id = p_request_id;
    return 'withdrawn';
  end if;

  select *
  into target_trip
  from public.trips
  where id = request_record.trip_id
  for update;

  if target_trip.status <> 'published' or target_trip.open_seats <= 0 then
    raise exception 'This trip no longer has an open seat';
  end if;

  update public.trips
  set confirmed_traveler_count = confirmed_traveler_count + 1
  where id = target_trip.id;

  next_status := 'confirmed';
  update public.trip_join_requests
  set status = next_status,
      traveler_decided_at = now()
  where id = p_request_id;

  return next_status;
end;
$$;

create or replace function public.withdraw_join_request(p_request_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_record public.trip_join_requests;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select *
  into request_record
  from public.trip_join_requests
  where id = p_request_id
  for update;

  if request_record.id is null then
    raise exception 'Join request not found';
  end if;

  if request_record.traveler_id <> (select auth.uid())
    or request_record.status <> 'pending_host' then
    raise exception 'Only a pending traveler request can be withdrawn';
  end if;

  update public.trip_join_requests
  set status = 'withdrawn',
      traveler_decided_at = now()
  where id = p_request_id;

  return 'withdrawn';
end;
$$;

revoke all on function public.create_join_request(uuid, text) from public;
grant execute on function public.create_join_request(uuid, text) to authenticated;

revoke all on function public.review_join_request(uuid, boolean) from public;
grant execute on function public.review_join_request(uuid, boolean) to authenticated;

revoke all on function public.confirm_join_request(uuid, boolean) from public;
grant execute on function public.confirm_join_request(uuid, boolean) to authenticated;

revoke all on function public.withdraw_join_request(uuid) from public;
grant execute on function public.withdraw_join_request(uuid) to authenticated;
