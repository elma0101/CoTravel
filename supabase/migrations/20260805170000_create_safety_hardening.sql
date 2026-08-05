create table public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_user_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_user_id)
);

create table public.safety_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  subject_user_id uuid not null references public.profiles (id) on delete cascade,
  trip_id uuid references public.trips (id) on delete set null,
  reason text not null,
  details text not null,
  status text not null default 'submitted',
  moderator_notes text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint safety_reports_not_self check (reporter_id <> subject_user_id),
  constraint safety_reports_reason_valid check (
    reason in (
      'harassment',
      'suspicious_profile',
      'unsafe_plan',
      'spam',
      'other'
    )
  ),
  constraint safety_reports_details_length check (
    char_length(details) between 10 and 1000
  ),
  constraint safety_reports_status_valid check (
    status in ('submitted', 'in_review', 'resolved', 'dismissed')
  ),
  constraint safety_reports_moderator_notes_length check (
    moderator_notes is null or char_length(moderator_notes) <= 2000
  )
);

create table public.analytics_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  event_name text not null,
  trip_id uuid references public.trips (id) on delete set null,
  properties jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  constraint analytics_events_name_valid check (
    event_name in (
      'preview_signed_in',
      'profile_completed',
      'profile_verified',
      'trip_published',
      'join_request_submitted',
      'trip_place_confirmed',
      'group_created',
      'conversation_opened',
      'safety_report_submitted',
      'user_blocked'
    )
  ),
  constraint analytics_events_properties_object check (
    jsonb_typeof(properties) = 'object'
  ),
  constraint analytics_events_properties_size check (
    octet_length(properties::text) <= 2000
  )
);

create index user_blocks_blocked_user_idx
on public.user_blocks (blocked_user_id, blocker_id);

create index safety_reports_moderation_queue_idx
on public.safety_reports (status, created_at);

create index safety_reports_reporter_idx
on public.safety_reports (reporter_id, created_at desc);

create index analytics_events_name_time_idx
on public.analytics_events (event_name, occurred_at desc);

create index analytics_events_trip_idx
on public.analytics_events (trip_id, occurred_at desc)
where trip_id is not null;

create trigger safety_reports_set_updated_at
before update on public.safety_reports
for each row execute function public.set_updated_at();

alter table public.user_blocks enable row level security;
alter table public.safety_reports enable row level security;
alter table public.analytics_events enable row level security;

grant select, update on public.safety_reports to service_role;
grant select on public.user_blocks to service_role;
grant select on public.analytics_events to service_role;

create or replace function public.is_user_blocked_between(
  p_left_user_id uuid,
  p_right_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null
      or (select auth.uid()) not in (p_left_user_id, p_right_user_id)
    then false
    else exists (
      select 1
      from public.user_blocks
      where (
        blocker_id = p_left_user_id
        and blocked_user_id = p_right_user_id
      ) or (
        blocker_id = p_right_user_id
        and blocked_user_id = p_left_user_id
      )
    )
  end;
$$;

revoke all on function public.is_user_blocked_between(uuid, uuid) from public;
grant execute on function public.is_user_blocked_between(uuid, uuid)
to authenticated;

drop policy "Authenticated users can read completed profiles"
on public.profiles;

create policy "Authenticated users can read safe completed profiles"
on public.profiles
for select
to authenticated
using (
  id = (select auth.uid())
  or (
    onboarding_completed_at is not null
    and not public.is_user_blocked_between(id, (select auth.uid()))
  )
);

drop policy "Authenticated users can discover published trips"
on public.trips;

create policy "Authenticated users can discover safe published trips"
on public.trips
for select
to authenticated
using (
  host_id = (select auth.uid())
  or (
    status = 'published'
    and not public.is_user_blocked_between(host_id, (select auth.uid()))
  )
);

drop policy "Authenticated users can read visible trip stops"
on public.trip_stops;

create policy "Authenticated users can read safe visible trip stops"
on public.trip_stops
for select
to authenticated
using (
  exists (
    select 1
    from public.trips
    where trips.id = trip_stops.trip_id
      and (
        trips.host_id = (select auth.uid())
        or (
          trips.status = 'published'
          and not public.is_user_blocked_between(
            trips.host_id,
            (select auth.uid())
          )
        )
      )
  )
);

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
    from public.trip_join_requests as request
    join public.trips as trip on trip.id = request.trip_id
    where request.trip_id = p_trip_id
      and request.traveler_id = (select auth.uid())
      and request.status = 'confirmed'
      and not public.is_user_blocked_between(
        trip.host_id,
        (select auth.uid())
      )
  );
$$;

create or replace function public.prevent_blocked_join_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_host_id uuid;
begin
  select host_id
  into target_host_id
  from public.trips
  where id = new.trip_id;

  if public.is_user_blocked_between(new.traveler_id, target_host_id) then
    raise exception 'A join request cannot be created between blocked users';
  end if;

  return new;
end;
$$;

create trigger trip_join_requests_prevent_blocked_users
before insert on public.trip_join_requests
for each row execute function public.prevent_blocked_join_request();

revoke all on function public.prevent_blocked_join_request() from public;

create or replace function public.my_blocked_users()
returns table (
  blocked_user_id uuid,
  display_name text,
  blocked_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    block.blocked_user_id,
    coalesce(profile.display_name, 'CoTravel member'),
    block.created_at
  from public.user_blocks as block
  join public.profiles as profile on profile.id = block.blocked_user_id
  where block.blocker_id = (select auth.uid())
  order by block.created_at desc;
$$;

create or replace function public.my_safety_reports()
returns table (
  report_id uuid,
  subject_user_id uuid,
  subject_name text,
  trip_id uuid,
  trip_title text,
  reason text,
  details text,
  status text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    report.id,
    report.subject_user_id,
    coalesce(profile.display_name, 'CoTravel member'),
    report.trip_id,
    trip.title,
    report.reason,
    report.details,
    report.status,
    report.created_at
  from public.safety_reports as report
  join public.profiles as profile on profile.id = report.subject_user_id
  left join public.trips as trip on trip.id = report.trip_id
  where report.reporter_id = (select auth.uid())
  order by report.created_at desc;
$$;

create or replace function public.submit_safety_report(
  p_subject_user_id uuid,
  p_trip_id uuid,
  p_reason text,
  p_details text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_report_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_subject_user_id = (select auth.uid()) then
    raise exception 'You cannot report your own profile';
  end if;

  if not exists (
    select 1 from public.profiles where id = p_subject_user_id
  ) then
    raise exception 'The reported profile was not found';
  end if;

  if p_reason not in (
    'harassment',
    'suspicious_profile',
    'unsafe_plan',
    'spam',
    'other'
  ) then
    raise exception 'Choose a valid report reason';
  end if;

  if char_length(trim(p_details)) not between 10 and 1000 then
    raise exception 'Report details must contain 10 to 1000 characters';
  end if;

  if p_trip_id is not null and not exists (
    select 1
    from public.trips
    where id = p_trip_id
      and (
        host_id = p_subject_user_id
        or host_id = (select auth.uid())
      )
  ) then
    raise exception 'The report does not match this trip';
  end if;

  insert into public.safety_reports (
    reporter_id,
    subject_user_id,
    trip_id,
    reason,
    details
  )
  values (
    (select auth.uid()),
    p_subject_user_id,
    p_trip_id,
    p_reason,
    trim(p_details)
  )
  returning id into created_report_id;

  return created_report_id;
end;
$$;

create or replace function public.block_user(p_blocked_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_blocked_user_id = (select auth.uid()) then
    raise exception 'You cannot block your own profile';
  end if;

  if not exists (
    select 1 from public.profiles where id = p_blocked_user_id
  ) then
    raise exception 'The profile was not found';
  end if;

  insert into public.user_blocks (blocker_id, blocked_user_id)
  values ((select auth.uid()), p_blocked_user_id)
  on conflict (blocker_id, blocked_user_id) do nothing;
end;
$$;

create or replace function public.unblock_user(p_blocked_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  delete from public.user_blocks
  where blocker_id = (select auth.uid())
    and blocked_user_id = p_blocked_user_id;
end;
$$;

create or replace function public.track_product_event(
  p_event_name text,
  p_trip_id uuid,
  p_properties jsonb
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

  if p_event_name not in (
    'preview_signed_in',
    'profile_completed',
    'profile_verified',
    'trip_published',
    'join_request_submitted',
    'trip_place_confirmed',
    'group_created',
    'conversation_opened',
    'safety_report_submitted',
    'user_blocked'
  ) then
    raise exception 'Unsupported product event';
  end if;

  if jsonb_typeof(coalesce(p_properties, '{}'::jsonb)) <> 'object'
    or octet_length(coalesce(p_properties, '{}'::jsonb)::text) > 2000 then
    raise exception 'Event properties must be a small JSON object';
  end if;

  insert into public.analytics_events (
    actor_id,
    event_name,
    trip_id,
    properties
  )
  values (
    (select auth.uid()),
    p_event_name,
    p_trip_id,
    coalesce(p_properties, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.my_blocked_users() from public;
grant execute on function public.my_blocked_users() to authenticated;

revoke all on function public.my_safety_reports() from public;
grant execute on function public.my_safety_reports() to authenticated;

revoke all on function public.submit_safety_report(uuid, uuid, text, text)
from public;
grant execute on function public.submit_safety_report(uuid, uuid, text, text)
to authenticated;

revoke all on function public.block_user(uuid) from public;
grant execute on function public.block_user(uuid) to authenticated;

revoke all on function public.unblock_user(uuid) from public;
grant execute on function public.unblock_user(uuid) to authenticated;

revoke all on function public.track_product_event(text, uuid, jsonb)
from public;
grant execute on function public.track_product_event(text, uuid, jsonb)
to authenticated;

create view public.moderation_report_queue
with (security_invoker = true)
as
select
  report.id,
  report.created_at,
  report.status,
  report.reason,
  report.details,
  report.reporter_id,
  reporter.display_name as reporter_name,
  report.subject_user_id,
  subject.display_name as subject_name,
  report.trip_id,
  trip.title as trip_title,
  report.moderator_notes,
  report.reviewed_at
from public.safety_reports as report
join public.profiles as reporter on reporter.id = report.reporter_id
join public.profiles as subject on subject.id = report.subject_user_id
left join public.trips as trip on trip.id = report.trip_id;

revoke all on public.moderation_report_queue from anon, authenticated;
grant select on public.moderation_report_queue to service_role;
