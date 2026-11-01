-- Trip lifecycle, traveler departures with a cancellation window, and an in-app
-- notification inbox. Notifications store facts, not sentences, so the client can
-- translate them.

alter table public.trip_join_requests
  add column left_at timestamptz,
  add column left_late boolean not null default false;

alter table public.trip_join_requests
  drop constraint trip_join_requests_status_valid;
alter table public.trip_join_requests
  add constraint trip_join_requests_status_valid check (
    status in (
      'pending_host',
      'pending_traveler',
      'confirmed',
      'declined',
      'withdrawn',
      'left'
    )
  );

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  trip_id uuid references public.trips (id) on delete cascade,
  trip_title text not null,
  actor_name text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_kind_valid check (
    kind in (
      'join_request_received',
      'request_approved',
      'request_declined',
      'traveler_confirmed',
      'traveler_declined',
      'traveler_withdrew',
      'traveler_left',
      'traveler_left_late',
      'trip_updated',
      'trip_cancelled'
    )
  )
);

create index notifications_user_created_idx
on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;

create policy "Users can read their own notifications"
on public.notifications
for select
to authenticated
using (user_id = (select auth.uid()));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end;
$$;

create or replace function public.mark_notifications_read(
  p_notification_id uuid default null
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

  update public.notifications
  set read_at = now()
  where user_id = (select auth.uid())
    and read_at is null
    and (p_notification_id is null or id = p_notification_id);
end;
$$;

revoke all on function public.mark_notifications_read(uuid)
from public, anon;
grant execute on function public.mark_notifications_read(uuid)
to authenticated;

-- Join request events become notifications for the other party.
create or replace function public.notify_join_request_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_trip public.trips;
  traveler_name text;
  recipient_id uuid;
  notification_kind text;
begin
  select * into target_trip from public.trips where id = new.trip_id;

  select coalesce(display_name, 'A traveler')
  into traveler_name
  from public.profiles
  where id = new.traveler_id;

  if tg_op = 'INSERT' then
    recipient_id := target_trip.host_id;
    notification_kind := 'join_request_received';
  elsif old.status = new.status then
    return new;
  elsif new.status = 'pending_traveler' then
    recipient_id := new.traveler_id;
    notification_kind := 'request_approved';
  elsif new.status = 'declined' then
    recipient_id := new.traveler_id;
    notification_kind := 'request_declined';
  elsif new.status = 'confirmed' then
    recipient_id := target_trip.host_id;
    notification_kind := 'traveler_confirmed';
  elsif new.status = 'withdrawn' and old.status = 'pending_traveler' then
    recipient_id := target_trip.host_id;
    notification_kind := 'traveler_declined';
  elsif new.status = 'withdrawn' then
    recipient_id := target_trip.host_id;
    notification_kind := 'traveler_withdrew';
  elsif new.status = 'left' then
    recipient_id := target_trip.host_id;
    notification_kind := case
      when new.left_late then 'traveler_left_late'
      else 'traveler_left'
    end;
  else
    return new;
  end if;

  insert into public.notifications (
    user_id,
    kind,
    trip_id,
    trip_title,
    actor_name
  )
  values (
    recipient_id,
    notification_kind,
    new.trip_id,
    target_trip.title,
    case
      when recipient_id = target_trip.host_id then traveler_name
      else (
        select display_name
        from public.profiles
        where id = target_trip.host_id
      )
    end
  );

  return new;
end;
$$;

create trigger trip_join_requests_notify
after insert or update of status on public.trip_join_requests
for each row execute function public.notify_join_request_change();

-- A trip that has started can no longer gain requests or confirmed travelers.
create or replace function public.require_upcoming_trip()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('pending_host', 'confirmed') and exists (
    select 1
    from public.trips
    where id = new.trip_id
      and start_date < current_date
  ) then
    raise exception 'This trip has already started';
  end if;

  return new;
end;
$$;

create trigger trip_join_requests_require_upcoming
before insert or update of status on public.trip_join_requests
for each row execute function public.require_upcoming_trip();

revoke all on function public.notify_join_request_change()
from public, anon, authenticated;
revoke all on function public.require_upcoming_trip()
from public, anon, authenticated;

-- Travelers keep access to a trip they asked to join after it is cancelled, so
-- their requests and notifications still open.
create or replace function public.has_trip_request(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trip_join_requests as request
    join public.trips as trip on trip.id = request.trip_id
    where request.trip_id = p_trip_id
      and request.traveler_id = (select auth.uid())
      and not public.is_user_blocked_between(
        trip.host_id,
        (select auth.uid())
      )
  );
$$;

revoke all on function public.has_trip_request(uuid) from public, anon;
grant execute on function public.has_trip_request(uuid) to authenticated;

create policy "Travelers can read trips they requested"
on public.trips
for select
to authenticated
using (public.has_trip_request(id));

create policy "Travelers can read stops of trips they requested"
on public.trip_stops
for select
to authenticated
using (public.has_trip_request(trip_id));

-- Sends one notification per confirmed traveler. Not callable through the API.
create or replace function public.notify_confirmed_travelers(
  p_trip public.trips,
  p_kind text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (
    user_id,
    kind,
    trip_id,
    trip_title,
    actor_name
  )
  select
    request.traveler_id,
    p_kind,
    p_trip.id,
    p_trip.title,
    (select display_name from public.profiles where id = p_trip.host_id)
  from public.trip_join_requests as request
  where request.trip_id = p_trip.id
    and request.status = 'confirmed';
$$;

revoke all on function public.notify_confirmed_travelers(public.trips, text)
from public, anon, authenticated;

create or replace function public.post_trip_system_message(
  p_trip_id uuid,
  p_body text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.chat_messages (
    conversation_id,
    sender_id,
    sender_name,
    body,
    message_type
  )
  select id, null, null, p_body, 'system'
  from public.trip_conversations
  where trip_id = p_trip_id;
$$;

revoke all on function public.post_trip_system_message(uuid, text)
from public, anon, authenticated;

create or replace function public.update_trip(
  p_trip_id uuid,
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
  target_trip public.trips;
  updated_trip public.trips;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select * into target_trip
  from public.trips
  where id = p_trip_id
  for update;

  if target_trip.id is null then
    raise exception 'Trip not found';
  end if;

  if target_trip.host_id <> (select auth.uid()) then
    raise exception 'Only this trip host can edit the trip';
  end if;

  if target_trip.status <> 'published' then
    raise exception 'Only a published trip can be edited';
  end if;

  if target_trip.start_date < current_date then
    raise exception 'A trip that has started cannot be edited';
  end if;

  if p_capacity < target_trip.confirmed_traveler_count + 1 then
    raise exception 'Capacity cannot be lower than the confirmed group';
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

  update public.trips
  set title = trim(p_title),
      origin_city = trim(p_origin_city),
      destination_city = trim(
        p_stops -> (jsonb_array_length(p_stops) - 1) ->> 'city'
      ),
      start_date = p_start_date,
      end_date = p_end_date,
      capacity = p_capacity,
      lodging_total = p_lodging_total,
      transport_total = p_transport_total,
      currency = upper(trim(p_currency)),
      travel_style = trim(p_travel_style),
      summary = trim(p_summary)
  where id = p_trip_id
  returning * into updated_trip;

  delete from public.trip_stops where trip_id = p_trip_id;

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
    p_trip_id,
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
  from jsonb_array_elements(p_stops) with ordinality as stop;

  perform public.notify_confirmed_travelers(updated_trip, 'trip_updated');

  return p_trip_id;
end;
$$;

revoke all on function public.update_trip(
  uuid, text, text, date, date, jsonb, smallint, numeric, numeric, text, text, text
) from public, anon;
grant execute on function public.update_trip(
  uuid, text, text, date, date, jsonb, smallint, numeric, numeric, text, text, text
) to authenticated;

create or replace function public.cancel_trip(p_trip_id uuid)
returns void
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

  select * into target_trip
  from public.trips
  where id = p_trip_id
  for update;

  if target_trip.id is null then
    raise exception 'Trip not found';
  end if;

  if target_trip.host_id <> (select auth.uid()) then
    raise exception 'Only this trip host can cancel the trip';
  end if;

  if target_trip.status <> 'published' then
    raise exception 'Only a published trip can be cancelled';
  end if;

  update public.trips set status = 'cancelled' where id = p_trip_id;

  -- Each pending traveler is told through the join request trigger.
  update public.trip_join_requests
  set status = 'declined',
      host_decided_at = now()
  where trip_id = p_trip_id
    and status in ('pending_host', 'pending_traveler');

  perform public.notify_confirmed_travelers(target_trip, 'trip_cancelled');
  perform public.post_trip_system_message(
    p_trip_id,
    'The host cancelled this trip.'
  );
end;
$$;

revoke all on function public.cancel_trip(uuid) from public, anon;
grant execute on function public.cancel_trip(uuid) to authenticated;

-- Free until seven days before departure. Later departures are still allowed, and
-- are recorded as late and reported to the host.
create or replace function public.leave_trip(p_request_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_record public.trip_join_requests;
  target_trip public.trips;
  traveler_name text;
  is_late boolean;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select * into request_record
  from public.trip_join_requests
  where id = p_request_id
  for update;

  if request_record.id is null then
    raise exception 'Join request not found';
  end if;

  if request_record.traveler_id <> (select auth.uid()) then
    raise exception 'Only this traveler can leave the trip';
  end if;

  if request_record.status <> 'confirmed' then
    raise exception 'Only a confirmed traveler can leave the trip';
  end if;

  select * into target_trip
  from public.trips
  where id = request_record.trip_id
  for update;

  if target_trip.start_date < current_date then
    raise exception 'A trip that has started cannot be left';
  end if;

  is_late := current_date > target_trip.start_date - 7;

  update public.trips
  set confirmed_traveler_count = confirmed_traveler_count - 1
  where id = target_trip.id;

  update public.trip_join_requests
  set status = 'left',
      left_at = now(),
      left_late = is_late
  where id = p_request_id;

  delete from public.conversation_members as membership
  using public.trip_conversations as conversation
  where conversation.id = membership.conversation_id
    and conversation.trip_id = target_trip.id
    and membership.user_id = (select auth.uid());

  select coalesce(display_name, 'A traveler')
  into traveler_name
  from public.profiles
  where id = (select auth.uid());

  perform public.post_trip_system_message(
    target_trip.id,
    traveler_name || ' left the trip.'
  );

  return is_late;
end;
$$;

revoke all on function public.leave_trip(uuid) from public, anon;
grant execute on function public.leave_trip(uuid) to authenticated;
