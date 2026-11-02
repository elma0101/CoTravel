alter table public.profiles
add column verification_source text not null default 'none';
alter table public.profiles
add constraint profiles_verification_source_valid check (
  verification_source in ('none', 'linkedin_oidc', 'staging_allowlist')
);
update public.profiles
set verification_source = 'linkedin_oidc'
where linkedin_verified_at is not null;
-- Profile changes already go through complete_profile. Removing direct writes
-- prevents a modified client from setting its own verification timestamp.
revoke insert, update on public.profiles from authenticated;
create table public.app_environment_controls (
  id smallint primary key default 1,
  environment text not null default 'production',
  staging_linkedin_bypass_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint app_environment_controls_singleton check (id = 1),
  constraint app_environment_controls_environment_valid check (
    environment in ('production', 'staging')
  ),
  constraint app_environment_controls_bypass_only_in_staging check (
    not staging_linkedin_bypass_enabled or environment = 'staging'
  )
);
insert into public.app_environment_controls (
  id,
  environment,
  staging_linkedin_bypass_enabled
)
values (1, 'production', false)
on conflict (id) do nothing;
create trigger app_environment_controls_set_updated_at
before update on public.app_environment_controls
for each row execute function public.set_updated_at();
alter table public.app_environment_controls enable row level security;
revoke all on public.app_environment_controls from anon, authenticated;
grant select, insert, update, delete
on public.app_environment_controls to service_role;
create table public.staging_verification_allowlist (
  email text primary key,
  enabled boolean not null default true,
  expires_at timestamptz not null default (now() + interval '30 days'),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staging_verification_allowlist_normalized_email check (
    email = lower(trim(email))
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
  ),
  constraint staging_verification_allowlist_note_length check (
    note is null or char_length(note) <= 200
  )
);
create trigger staging_verification_allowlist_set_updated_at
before update on public.staging_verification_allowlist
for each row execute function public.set_updated_at();
alter table public.staging_verification_allowlist enable row level security;
revoke all on public.staging_verification_allowlist from anon, authenticated;
grant select, insert, update, delete
on public.staging_verification_allowlist to service_role;
create or replace function public.sync_my_linkedin_verification()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_email text;
  has_linkedin_identity boolean := false;
  has_staging_access boolean := false;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select exists (
    select 1
    from auth.identities
    where user_id = current_user_id
      and provider = 'linkedin_oidc'
  ) into has_linkedin_identity;

  select lower(trim(email))
  into current_email
  from auth.users
  where id = current_user_id;

  if not has_linkedin_identity and current_email is not null then
    select exists (
      select 1
      from public.app_environment_controls as controls
      join public.staging_verification_allowlist as allowlist
        on allowlist.email = current_email
      where controls.id = 1
        and controls.environment = 'staging'
        and controls.staging_linkedin_bypass_enabled
        and allowlist.enabled
        and allowlist.expires_at > now()
    ) into has_staging_access;
  end if;

  update public.profiles
  set
    linkedin_verified_at = case
      when has_linkedin_identity or has_staging_access
        then coalesce(linkedin_verified_at, now())
      else null
    end,
    verification_source = case
      when has_linkedin_identity then 'linkedin_oidc'
      when has_staging_access then 'staging_allowlist'
      else 'none'
    end
  where id = current_user_id;

  return has_linkedin_identity or has_staging_access;
end;
$$;
revoke all on function public.sync_my_linkedin_verification() from public;
grant execute on function public.sync_my_linkedin_verification()
to authenticated;
comment on table public.app_environment_controls is
'Service-only deployment guard. The staging verification bypass defaults to disabled and cannot be enabled while the row is marked production.';
comment on table public.staging_verification_allowlist is
'Service-only, expiring tester email allowlist. It grants temporary staging feature access but is not LinkedIn verification.';
comment on column public.profiles.verification_source is
'Records whether the verification timestamp came from LinkedIn OIDC or the temporary staging allowlist.';
create or replace view public.beta_kpi_dashboard
with (security_invoker = true)
as
with profile_metrics as (
  select count(*) filter (
    where onboarding_completed_at is not null
      and linkedin_verified_at is not null
      and verification_source = 'linkedin_oidc'
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
'Service-only controlled-beta KPIs. Temporary staging allowlist access never counts as verified identity evidence.';
