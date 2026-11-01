-- Optional, self-declared trust details and a record of which terms were accepted.
alter table public.profiles
  add column instagram_handle text,
  add column occupation text,
  add column terms_version text,
  add column terms_accepted_at timestamptz,
  add constraint profiles_instagram_handle_format check (
    instagram_handle is null or instagram_handle ~ '^[a-z0-9._]{1,30}$'
  ),
  add constraint profiles_occupation_length check (
    occupation is null or char_length(occupation) <= 80
  );

drop function public.complete_profile(text, text, text, text[], text[], text);

create function public.complete_profile(
  p_display_name text,
  p_bio text,
  p_home_city text,
  p_travel_styles text[],
  p_languages text[],
  p_avatar_path text default null,
  p_instagram_handle text default null,
  p_occupation text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  completed_profile public.profiles;
  normalized_handle text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if char_length(trim(p_display_name)) not between 2 and 60 then
    raise exception 'Display name must contain 2 to 60 characters';
  end if;

  if char_length(trim(p_bio)) > 280 then
    raise exception 'Bio must not exceed 280 characters';
  end if;

  if char_length(trim(p_home_city)) > 80 then
    raise exception 'Home city must not exceed 80 characters';
  end if;

  if cardinality(coalesce(p_travel_styles, '{}')) > 5 then
    raise exception 'Choose no more than 5 travel styles';
  end if;

  if cardinality(coalesce(p_languages, '{}')) > 8 then
    raise exception 'Choose no more than 8 languages';
  end if;

  if char_length(trim(p_occupation)) > 80 then
    raise exception 'Occupation must not exceed 80 characters';
  end if;

  normalized_handle := nullif(lower(ltrim(trim(p_instagram_handle), '@')), '');
  if normalized_handle !~ '^[a-z0-9._]{1,30}$' then
    raise exception 'Enter a valid Instagram username';
  end if;

  insert into public.profiles (
    id,
    display_name,
    bio,
    home_city,
    travel_styles,
    languages,
    avatar_path,
    instagram_handle,
    occupation,
    onboarding_completed_at
  )
  values (
    (select auth.uid()),
    trim(p_display_name),
    nullif(trim(p_bio), ''),
    nullif(trim(p_home_city), ''),
    coalesce(p_travel_styles, '{}'),
    coalesce(p_languages, '{}'),
    p_avatar_path,
    normalized_handle,
    nullif(trim(p_occupation), ''),
    now()
  )
  on conflict (id) do update set
    display_name = excluded.display_name,
    bio = excluded.bio,
    home_city = excluded.home_city,
    travel_styles = excluded.travel_styles,
    languages = excluded.languages,
    avatar_path = coalesce(excluded.avatar_path, public.profiles.avatar_path),
    instagram_handle = excluded.instagram_handle,
    occupation = excluded.occupation,
    onboarding_completed_at = coalesce(
      public.profiles.onboarding_completed_at,
      excluded.onboarding_completed_at
    )
  returning * into completed_profile;

  return completed_profile;
end;
$$;

revoke all on function public.complete_profile(
  text, text, text, text[], text[], text, text, text
) from public, anon;
grant execute on function public.complete_profile(
  text, text, text, text[], text[], text, text, text
) to authenticated;

create or replace function public.accept_terms(p_version text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_version is null or char_length(trim(p_version)) not between 1 and 40 then
    raise exception 'A terms version is required';
  end if;

  update public.profiles
  set terms_version = trim(p_version),
      terms_accepted_at = now()
  where id = (select auth.uid());
end;
$$;

revoke all on function public.accept_terms(text) from public, anon;
grant execute on function public.accept_terms(text) to authenticated;

-- Facts shown instead of a reputation score. Blocked pairs see nothing.
create or replace function public.member_trust_facts(p_user_id uuid)
returns table (
  member_since timestamptz,
  trips_hosted integer,
  trips_joined integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.created_at,
    (
      select count(*)::integer
      from public.trips as trip
      where trip.host_id = profile.id
        and trip.status <> 'cancelled'
    ),
    (
      select count(*)::integer
      from public.trip_join_requests as request
      where request.traveler_id = profile.id
        and request.status = 'confirmed'
    )
  from public.profiles as profile
  where profile.id = p_user_id
    and (select auth.uid()) is not null
    and not public.is_user_blocked_between(profile.id, (select auth.uid()));
$$;

revoke all on function public.member_trust_facts(uuid) from public, anon;
grant execute on function public.member_trust_facts(uuid) to authenticated;

-- A report outlives either party, so deleting an account cannot erase a complaint.
alter table public.safety_reports
  alter column reporter_id drop not null,
  alter column subject_user_id drop not null,
  drop constraint safety_reports_reporter_id_fkey,
  drop constraint safety_reports_subject_user_id_fkey,
  add constraint safety_reports_reporter_id_fkey
    foreign key (reporter_id) references public.profiles (id) on delete set null,
  add constraint safety_reports_subject_user_id_fkey
    foreign key (subject_user_id) references public.profiles (id) on delete set null;

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
  left join public.profiles as profile on profile.id = report.subject_user_id
  left join public.trips as trip on trip.id = report.trip_id
  where report.reporter_id = (select auth.uid())
  order by report.created_at desc;
$$;

create or replace view public.moderation_report_queue
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
left join public.profiles as reporter on reporter.id = report.reporter_id
left join public.profiles as subject on subject.id = report.subject_user_id
left join public.trips as trip on trip.id = report.trip_id;

-- Deleting a hosted trip would strand its group, so hosts cancel those first.
-- Other trips the host created go with the account through the foreign keys.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  confirmed_request record;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if exists (
    select 1
    from public.trips
    where host_id = caller_id
      and status <> 'cancelled'
      and start_date >= current_date
      and confirmed_traveler_count > 0
  ) then
    raise exception 'Cancel your upcoming trips with confirmed travelers before deleting your account';
  end if;

  -- Leaving first frees the seat and tells the host.
  for confirmed_request in
    select request.id
    from public.trip_join_requests as request
    join public.trips as trip on trip.id = request.trip_id
    where request.traveler_id = caller_id
      and request.status = 'confirmed'
      and trip.start_date >= current_date
  loop
    perform public.leave_trip(confirmed_request.id);
  end loop;

  -- Messages stay readable for the group but no longer name this person.
  update public.chat_messages
  set sender_name = 'Former member'
  where sender_id = caller_id;

  delete from auth.users where id = caller_id;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
