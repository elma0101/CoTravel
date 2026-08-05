create table public.beta_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_area text not null,
  safe_informed_score smallint not null,
  comments text,
  created_at timestamptz not null default now(),
  constraint beta_feedback_experience_area_valid check (
    experience_area in ('discovery', 'joining', 'hosting', 'coordination')
  ),
  constraint beta_feedback_score_valid check (
    safe_informed_score between 1 and 5
  ),
  constraint beta_feedback_comments_length check (
    comments is null or char_length(comments) <= 1000
  )
);

create index beta_feedback_created_at_idx
on public.beta_feedback (created_at desc);

create index beta_feedback_user_created_at_idx
on public.beta_feedback (user_id, created_at desc);

alter table public.beta_feedback enable row level security;

revoke all on public.beta_feedback from anon, authenticated;
grant select on public.profiles, public.trips, public.trip_stops,
  public.beta_feedback to service_role;

create or replace function public.submit_beta_feedback(
  p_experience_area text,
  p_safe_informed_score smallint,
  p_comments text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_feedback_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_experience_area not in (
    'discovery',
    'joining',
    'hosting',
    'coordination'
  ) then
    raise exception 'Choose a valid beta experience';
  end if;

  if p_safe_informed_score not between 1 and 5 then
    raise exception 'Choose a rating from 1 to 5';
  end if;

  if char_length(trim(coalesce(p_comments, ''))) > 1000 then
    raise exception 'Keep your note under 1000 characters';
  end if;

  insert into public.beta_feedback (
    user_id,
    experience_area,
    safe_informed_score,
    comments
  )
  values (
    (select auth.uid()),
    p_experience_area,
    p_safe_informed_score,
    nullif(trim(coalesce(p_comments, '')), '')
  )
  returning id into created_feedback_id;

  return created_feedback_id;
end;
$$;

create or replace function public.my_beta_feedback()
returns table (
  feedback_id uuid,
  experience_area text,
  safe_informed_score smallint,
  comments text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    feedback.id,
    feedback.experience_area,
    feedback.safe_informed_score,
    feedback.comments,
    feedback.created_at
  from public.beta_feedback as feedback
  where feedback.user_id = (select auth.uid())
  order by feedback.created_at desc;
$$;

revoke all on function public.submit_beta_feedback(text, smallint, text)
from public;
grant execute on function public.submit_beta_feedback(text, smallint, text)
to authenticated;

revoke all on function public.my_beta_feedback() from public;
grant execute on function public.my_beta_feedback() to authenticated;

create view public.beta_kpi_dashboard
with (security_invoker = true)
as
with profile_metrics as (
  select count(*) filter (
    where onboarding_completed_at is not null
      and linkedin_verified_at is not null
  ) as verified_profiles
  from public.profiles
),
trip_metrics as (
  select
    count(*) filter (
      where status = 'published'
        and exists (
          select 1
          from public.trip_stops
          where trip_stops.trip_id = trips.id
        )
    ) as published_itineraries,
    count(*) filter (
      where status = 'published'
        and confirmed_traveler_count > 0
        and exists (
          select 1
          from public.trip_stops
          where trip_stops.trip_id = trips.id
        )
    ) as matched_itineraries
  from public.trips
),
latest_feedback as (
  select distinct on (user_id)
    user_id,
    safe_informed_score
  from public.beta_feedback
  order by user_id, created_at desc
),
feedback_metrics as (
  select
    count(*) as feedback_responses,
    count(*) filter (where safe_informed_score >= 4) as positive_responses
  from latest_feedback
),
metrics as (
  select
    profile_metrics.verified_profiles,
    trip_metrics.published_itineraries,
    trip_metrics.matched_itineraries,
    feedback_metrics.feedback_responses,
    feedback_metrics.positive_responses,
    round(
      100.0 * trip_metrics.matched_itineraries
        / nullif(trip_metrics.published_itineraries, 0),
      1
    ) as matched_itinerary_percent,
    round(
      100.0 * feedback_metrics.positive_responses
        / nullif(feedback_metrics.feedback_responses, 0),
      1
    ) as positive_safe_informed_percent
  from profile_metrics, trip_metrics, feedback_metrics
)
select
  verified_profiles,
  published_itineraries,
  matched_itineraries,
  matched_itinerary_percent,
  feedback_responses,
  positive_responses,
  positive_safe_informed_percent,
  verified_profiles >= 50 as verified_profiles_target_met,
  published_itineraries >= 15 as published_itineraries_target_met,
  coalesce(matched_itinerary_percent >= 30, false)
    as matched_itineraries_target_met,
  coalesce(positive_safe_informed_percent > 80, false)
    as safe_informed_target_met,
  feedback_responses >= 20 as feedback_sample_ready,
  verified_profiles >= 50
    and published_itineraries >= 15
    and coalesce(matched_itinerary_percent >= 30, false)
    and coalesce(positive_safe_informed_percent > 80, false)
    as all_spec_targets_met
from metrics;

revoke all on public.beta_kpi_dashboard from anon, authenticated;
grant select on public.beta_kpi_dashboard to service_role;

comment on view public.beta_kpi_dashboard is
'Service-only controlled-beta KPIs. Only each account''s latest response is counted. Positive means a safe/informed score of 4 or 5. The 20-response sample flag is an operational readout guardrail, not a product-spec KPI.';

create or replace function public.seed_controlled_beta_trips(
  p_host_id uuid,
  p_environment text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  seed_trip record;
  created_trip_id uuid;
  inserted_count integer := 0;
begin
  if p_environment <> 'staging' then
    raise exception 'Controlled beta seed data can only target staging';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = p_host_id
      and onboarding_completed_at is not null
      and linkedin_verified_at is not null
  ) then
    raise exception 'Choose a complete, verified staging host profile';
  end if;

  for seed_trip in
    select value as item
    from jsonb_array_elements(
      '[
        {"title":"[Beta] Chefchaouen slow weekend","origin":"Tangier","destination":"Chefchaouen","offset":30,"days":3,"capacity":5,"lodging":4200,"transport":1600,"style":"Culture"},
        {"title":"[Beta] Essaouira coast and food","origin":"Marrakech","destination":"Essaouira","offset":35,"days":4,"capacity":6,"lodging":5800,"transport":2200,"style":"Food"},
        {"title":"[Beta] High Atlas village trail","origin":"Marrakech","destination":"Imlil","offset":40,"days":4,"capacity":5,"lodging":3600,"transport":1800,"style":"Hiking"},
        {"title":"[Beta] Dades valley slow road","origin":"Ouarzazate","destination":"Boumalne Dades","offset":45,"days":5,"capacity":6,"lodging":6200,"transport":3200,"style":"Road trips"},
        {"title":"[Beta] Fes craft and kitchens","origin":"Rabat","destination":"Fes","offset":50,"days":4,"capacity":5,"lodging":4800,"transport":1900,"style":"Culture"},
        {"title":"[Beta] Marrakech market table","origin":"Casablanca","destination":"Marrakech","offset":55,"days":3,"capacity":4,"lodging":3900,"transport":1700,"style":"Food"},
        {"title":"[Beta] Agafay under the stars","origin":"Marrakech","destination":"Agafay","offset":60,"days":3,"capacity":6,"lodging":5400,"transport":2100,"style":"Nature"},
        {"title":"[Beta] Tangier stories weekend","origin":"Rabat","destination":"Tangier","offset":65,"days":4,"capacity":5,"lodging":5200,"transport":2000,"style":"Culture"},
        {"title":"[Beta] Ouarzazate cinema route","origin":"Marrakech","destination":"Ouarzazate","offset":70,"days":5,"capacity":6,"lodging":6000,"transport":3000,"style":"Road trips"},
        {"title":"[Beta] Merzouga desert rhythm","origin":"Errachidia","destination":"Merzouga","offset":75,"days":4,"capacity":6,"lodging":6500,"transport":2600,"style":"Nature"},
        {"title":"[Beta] Ifrane cedar escape","origin":"Fes","destination":"Ifrane","offset":80,"days":3,"capacity":5,"lodging":4100,"transport":1500,"style":"Nature"},
        {"title":"[Beta] Rabat design walk","origin":"Casablanca","destination":"Rabat","offset":85,"days":3,"capacity":4,"lodging":3800,"transport":1200,"style":"Culture"},
        {"title":"[Beta] El Jadida heritage coast","origin":"Casablanca","destination":"El Jadida","offset":90,"days":4,"capacity":5,"lodging":4600,"transport":1700,"style":"Culture"},
        {"title":"[Beta] Akchour water and trails","origin":"Tetouan","destination":"Akchour","offset":95,"days":3,"capacity":5,"lodging":3400,"transport":1400,"style":"Hiking"},
        {"title":"[Beta] Souss surf trail","origin":"Agadir","destination":"Taghazout","offset":100,"days":5,"capacity":6,"lodging":5700,"transport":1800,"style":"Surf"}
      ]'::jsonb
    )
  loop
    if not exists (
      select 1
      from public.trips
      where host_id = p_host_id
        and title = seed_trip.item ->> 'title'
        and status <> 'cancelled'
    ) then
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
        summary,
        status
      )
      values (
        p_host_id,
        seed_trip.item ->> 'title',
        seed_trip.item ->> 'origin',
        seed_trip.item ->> 'destination',
        current_date + (seed_trip.item ->> 'offset')::integer,
        current_date + (seed_trip.item ->> 'offset')::integer
          + (seed_trip.item ->> 'days')::integer - 1,
        (seed_trip.item ->> 'capacity')::smallint,
        (seed_trip.item ->> 'lodging')::numeric,
        (seed_trip.item ->> 'transport')::numeric,
        'MAD',
        seed_trip.item ->> 'style',
        'Representative controlled-beta itinerary using fictional planning details. Confirm every route and booking choice independently.',
        'published'
      )
      returning id into created_trip_id;

      insert into public.trip_stops (
        trip_id,
        position,
        city,
        arrival_date,
        notes
      )
      values (
        created_trip_id,
        1,
        seed_trip.item ->> 'destination',
        current_date + (seed_trip.item ->> 'offset')::integer,
        'Fictional beta seed stop; no booking is implied.'
      );

      inserted_count := inserted_count + 1;
    end if;
  end loop;

  return inserted_count;
end;
$$;

revoke all on function public.seed_controlled_beta_trips(uuid, text)
from public;
grant execute on function public.seed_controlled_beta_trips(uuid, text)
to service_role;

comment on function public.seed_controlled_beta_trips(uuid, text) is
'Idempotently creates 15 fictional staging itineraries for the controlled beta. Never call against production.';
