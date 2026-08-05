alter table public.analytics_events
drop constraint analytics_events_name_valid;

alter table public.analytics_events
add constraint analytics_events_name_valid check (
  event_name in (
    'preview_signed_in',
    'profile_completed',
    'profile_verified',
    'trip_builder_opened',
    'trip_published',
    'join_request_submitted',
    'trip_place_confirmed',
    'group_created',
    'conversation_opened',
    'safety_report_submitted',
    'user_blocked'
  )
);

create index analytics_events_actor_name_time_idx
on public.analytics_events (actor_id, event_name, occurred_at desc);

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
    'trip_builder_opened',
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

  if p_event_name = 'trip_builder_opened'
    and (
      p_trip_id is not null
      or coalesce(p_properties, '{}'::jsonb) <> '{}'::jsonb
    ) then
    raise exception 'Trip builder timing events cannot contain metadata';
  end if;

  if p_event_name = 'trip_published' and not exists (
    select 1
    from public.trips
    where id = p_trip_id
      and host_id = (select auth.uid())
  ) then
    raise exception 'Trip publication analytics must reference a hosted trip';
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

revoke all on function public.track_product_event(text, uuid, jsonb)
from public;
grant execute on function public.track_product_event(text, uuid, jsonb)
to authenticated;

grant select on public.trip_join_requests, public.trip_conversations
to service_role;

create view public.poc_evidence_dashboard
with (security_invoker = true)
as
with timing_samples as (
  select
    published.id as publication_event_id,
    published.actor_id,
    published.trip_id,
    extract(
      epoch from published.occurred_at - builder.occurred_at
    )::integer as completion_seconds
  from public.analytics_events as published
  join public.trips as trip
    on trip.id = published.trip_id
    and trip.host_id = published.actor_id
  join lateral (
    select opened.occurred_at
    from public.analytics_events as opened
    where opened.actor_id = published.actor_id
      and opened.event_name = 'trip_builder_opened'
      and opened.occurred_at <= published.occurred_at
      and opened.occurred_at >= published.occurred_at - interval '2 hours'
    order by opened.occurred_at desc
    limit 1
  ) as builder on true
  where published.event_name = 'trip_published'
),
timing_metrics as (
  select
    count(*)::integer as itinerary_timing_sample_count,
    count(*) filter (
      where completion_seconds <= 180
    )::integer as itinerary_under_three_minutes_count,
    round(
      100.0 * count(*) filter (where completion_seconds <= 180)
        / nullif(count(*), 0),
      1
    ) as itinerary_under_three_minutes_percent
  from timing_samples
),
request_metrics as (
  select
    count(*)::integer as join_request_count,
    count(*) filter (where status = 'confirmed')::integer
      as confirmed_request_count,
    count(distinct trip_id) filter (where status = 'confirmed')::integer
      as confirmed_group_count
  from public.trip_join_requests
),
conversation_metrics as (
  select count(distinct conversation.id)::integer
    as confirmed_conversation_count
  from public.trip_conversations as conversation
  join public.trip_join_requests as request
    on request.trip_id = conversation.trip_id
    and request.status = 'confirmed'
)
select
  beta.verified_profiles,
  beta.published_itineraries,
  beta.matched_itineraries,
  beta.matched_itinerary_percent,
  beta.feedback_responses,
  beta.positive_responses,
  beta.positive_safe_informed_percent,
  beta.verified_profiles_target_met,
  beta.published_itineraries_target_met,
  beta.matched_itineraries_target_met,
  beta.safe_informed_target_met,
  beta.feedback_sample_ready,
  beta.all_spec_targets_met,
  timing.itinerary_timing_sample_count,
  timing.itinerary_under_three_minutes_count,
  timing.itinerary_under_three_minutes_percent,
  timing.itinerary_timing_sample_count >= 5 as itinerary_timing_sample_ready,
  timing.itinerary_timing_sample_count >= 5
    and coalesce(timing.itinerary_under_three_minutes_percent >= 80, false)
    as itinerary_timing_target_met,
  requests.join_request_count,
  requests.confirmed_request_count,
  requests.confirmed_group_count,
  conversations.confirmed_conversation_count,
  requests.join_request_count > 0
    and requests.confirmed_group_count > 0
    and conversations.confirmed_conversation_count > 0
    as workflow_data_evidence_ready,
  beta.all_spec_targets_met
    and beta.feedback_sample_ready
    and timing.itinerary_timing_sample_count >= 5
    and coalesce(timing.itinerary_under_three_minutes_percent >= 80, false)
    and requests.join_request_count > 0
    and requests.confirmed_group_count > 0
    and conversations.confirmed_conversation_count > 0
    as poc_data_gate_ready
from public.beta_kpi_dashboard as beta
cross join timing_metrics as timing
cross join request_metrics as requests
cross join conversation_metrics as conversations;

revoke all on public.poc_evidence_dashboard from anon, authenticated;
grant select on public.poc_evidence_dashboard to service_role;

comment on view public.poc_evidence_dashboard is
'Service-only PoC evidence. The five-sample and 80-percent itinerary timing rule is an operational evidence guardrail, not an additional product-spec KPI.';

create table public.poc_validation_snapshots (
  id uuid primary key default gen_random_uuid(),
  captured_at timestamptz not null default now(),
  spec_targets_met boolean not null,
  feedback_sample_ready boolean not null,
  itinerary_timing_sample_count integer not null,
  itinerary_under_three_minutes_percent numeric(5, 1),
  itinerary_timing_target_met boolean not null,
  workflow_data_evidence_ready boolean not null,
  automated_checks_passed boolean not null,
  security_audit_passed boolean not null,
  open_release_blockers integer not null,
  decision_status text not null,
  note text,
  constraint poc_validation_snapshots_blockers_nonnegative check (
    open_release_blockers >= 0
  ),
  constraint poc_validation_snapshots_decision_valid check (
    decision_status in ('not_ready', 'ready_for_stakeholder_review')
  ),
  constraint poc_validation_snapshots_note_length check (
    note is null or char_length(note) <= 1000
  )
);

create index poc_validation_snapshots_captured_at_idx
on public.poc_validation_snapshots (captured_at desc);

alter table public.poc_validation_snapshots enable row level security;

revoke all on public.poc_validation_snapshots
from anon, authenticated, service_role;
grant select on public.poc_validation_snapshots to service_role;

create or replace function public.capture_poc_validation_snapshot(
  p_automated_checks_passed boolean,
  p_security_audit_passed boolean,
  p_open_release_blockers integer,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  evidence public.poc_evidence_dashboard%rowtype;
  created_snapshot_id uuid;
  next_decision_status text;
begin
  if p_open_release_blockers < 0 then
    raise exception 'Open release blockers cannot be negative';
  end if;

  if char_length(trim(coalesce(p_note, ''))) > 1000 then
    raise exception 'Snapshot note must contain at most 1000 characters';
  end if;

  select * into evidence from public.poc_evidence_dashboard;

  next_decision_status := case
    when evidence.poc_data_gate_ready
      and p_automated_checks_passed
      and p_security_audit_passed
      and p_open_release_blockers = 0
    then 'ready_for_stakeholder_review'
    else 'not_ready'
  end;

  insert into public.poc_validation_snapshots (
    spec_targets_met,
    feedback_sample_ready,
    itinerary_timing_sample_count,
    itinerary_under_three_minutes_percent,
    itinerary_timing_target_met,
    workflow_data_evidence_ready,
    automated_checks_passed,
    security_audit_passed,
    open_release_blockers,
    decision_status,
    note
  )
  values (
    evidence.all_spec_targets_met,
    evidence.feedback_sample_ready,
    evidence.itinerary_timing_sample_count,
    evidence.itinerary_under_three_minutes_percent,
    evidence.itinerary_timing_target_met,
    evidence.workflow_data_evidence_ready,
    p_automated_checks_passed,
    p_security_audit_passed,
    p_open_release_blockers,
    next_decision_status,
    nullif(trim(coalesce(p_note, '')), '')
  )
  returning id into created_snapshot_id;

  return created_snapshot_id;
end;
$$;

revoke all on function public.capture_poc_validation_snapshot(
  boolean,
  boolean,
  integer,
  text
) from public;
grant execute on function public.capture_poc_validation_snapshot(
  boolean,
  boolean,
  integer,
  text
) to service_role;

comment on table public.poc_validation_snapshots is
'Append-only PoC review records. A ready status permits stakeholder review, not automatic production expansion.';
