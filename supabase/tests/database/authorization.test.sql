-- Exercises the abuse cases in docs/security-audit.md against real Row Level
-- Security and RPCs. Run with `supabase test db`. Everything rolls back.
begin;

create extension if not exists pgtap with schema extensions;

select plan(69);

create function pg_temp.act_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated')::text,
    true
  );
  perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.act_as_system()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create function pg_temp.new_user(p_id uuid, p_name text, p_verified boolean)
returns void
language plpgsql
as $$
begin
  insert into auth.users (id, email)
  values (p_id, p_name || '@example.test');

  update public.profiles
  set display_name = p_name,
      bio = 'A test traveler profile.',
      home_city = 'Rabat',
      onboarding_completed_at = now(),
      linkedin_verified_at = case when p_verified then now() end
  where id = p_id;
end;
$$;

select pg_temp.new_user('00000000-0000-0000-0000-00000000000a', 'host', true);
select pg_temp.new_user('00000000-0000-0000-0000-00000000000b', 'traveler', true);
select pg_temp.new_user('00000000-0000-0000-0000-00000000000c', 'stranger', true);
select pg_temp.new_user('00000000-0000-0000-0000-00000000000d', 'second', true);
select pg_temp.new_user('00000000-0000-0000-0000-00000000000e', 'unverified', false);
select pg_temp.new_user('00000000-0000-0000-0000-00000000000f', 'blocked', true);

create temp table ids (name text primary key, id uuid not null);
grant all on ids to authenticated;

-- Verification cannot be self-granted.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000e');

select throws_ok(
  $$update public.profiles set linkedin_verified_at = now()
    where id = '00000000-0000-0000-0000-00000000000e'$$,
  '42501',
  null,
  'a user cannot mark their own profile as LinkedIn verified'
);
select throws_ok(
  $$update public.profiles set bio = 'changed'
    where id = '00000000-0000-0000-0000-00000000000a'$$,
  '42501',
  null,
  'a user cannot update another profile'
);
select throws_ok(
  $$insert into public.profiles (id, linkedin_verified_at)
    values ('00000000-0000-0000-0000-000000000099', now())$$,
  '42501',
  null,
  'a user cannot insert a pre-verified profile'
);
select is(
  public.sync_my_linkedin_verification(),
  false,
  'verification sync stays false without a linked identity'
);

-- Publishing is limited to verified hosts.

select throws_ok(
  $$select public.create_trip(
    'Unverified trip', 'Rabat', current_date + 10, current_date + 12,
    '[{"city":"Fes","arrival_date":"2099-01-01"}]'::jsonb, 3::smallint,
    100, 100, 'MAD', 'Culture', 'A summary that is long enough to pass.'
  )$$,
  'P0001',
  'A complete, verified profile is required to publish trips',
  'an unverified user cannot publish through the RPC'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select lives_ok(
  $$insert into ids
    select 'trip', public.create_trip(
      'Atlas villages', 'Marrakech', current_date + 10, current_date + 12,
      jsonb_build_array(jsonb_build_object(
        'city', 'Merzouga', 'arrival_date', current_date + 12
      )),
      2::smallint, 600, 300, 'MAD', 'Culture',
      'A summary that is long enough to pass.'
    )$$,
  'a verified host can publish a trip'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select throws_ok(
  $$update public.trips set title = 'Hijacked'
    where id = (select id from ids where name = 'trip')$$,
  '42501',
  null,
  'a traveler cannot change a trip directly'
);
select throws_ok(
  $$insert into public.trip_stops (trip_id, position, city, arrival_date)
    select id, 9, 'Nowhere', current_date + 11 from ids where name = 'trip'$$,
  '42501',
  null,
  'a traveler cannot add stops directly'
);

-- Mutual approval state machine.

select lives_ok(
  $$insert into ids
    select 'request', public.create_join_request(
      (select id from ids where name = 'trip'),
      'I would love to join this route with you.'
    )$$,
  'a verified traveler can request to join'
);
select throws_ok(
  $$select public.create_join_request(
    (select id from ids where name = 'trip'),
    'I would love to join this route a second time.'
  )$$,
  'P0001',
  'You already have an active request for this trip',
  'a traveler cannot hold two active requests'
);
select throws_ok(
  $$select public.review_join_request(
    (select id from ids where name = 'request'), true
  )$$,
  'P0001',
  'Only this trip host can review the request',
  'a traveler cannot approve their own request'
);
select throws_ok(
  $$select public.confirm_join_request(
    (select id from ids where name = 'request'), true
  )$$,
  'P0001',
  'This request is not awaiting traveler confirmation',
  'a traveler cannot confirm before host approval'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000c');

select is_empty(
  $$select id from public.trip_join_requests$$,
  'an unrelated account cannot read join requests'
);
select throws_ok(
  $$select public.review_join_request(
    (select id from ids where name = 'request'), true
  )$$,
  'P0001',
  'Only this trip host can review the request',
  'an unrelated account cannot approve a request'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000e');

select throws_ok(
  $$select public.create_join_request(
    (select id from ids where name = 'trip'),
    'I would love to join this route with you.'
  )$$,
  'P0001',
  'A complete, verified profile is required to join trips',
  'an unverified user cannot request to join'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select throws_ok(
  $$select public.create_join_request(
    (select id from ids where name = 'trip'),
    'I would love to join my own route as well.'
  )$$,
  'P0001',
  'Hosts cannot request to join their own trip',
  'a host cannot join their own trip'
);
select is(
  public.review_join_request((select id from ids where name = 'request'), true),
  'pending_traveler',
  'the host approval waits for the traveler'
);
select is(
  (select confirmed_traveler_count from public.trips
   where id = (select id from ids where name = 'trip')),
  0::smallint,
  'host approval alone does not take a seat'
);
select throws_ok(
  $$select public.confirm_join_request(
    (select id from ids where name = 'request'), true
  )$$,
  'P0001',
  'Only this traveler can confirm the request',
  'a host cannot confirm for the traveler'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000d');

select lives_ok(
  $$insert into ids
    select 'second_request', public.create_join_request(
      (select id from ids where name = 'trip'),
      'I would also love to join this route with you.'
    )$$,
  'another traveler can request the same last seat'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select is(
  public.review_join_request(
    (select id from ids where name = 'second_request'), true
  ),
  'pending_traveler',
  'the host can approve more travelers than seats'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select is(
  public.confirm_join_request((select id from ids where name = 'request'), true),
  'confirmed',
  'the traveler confirmation locks the seat'
);
select throws_ok(
  $$select public.confirm_join_request(
    (select id from ids where name = 'request'), true
  )$$,
  'P0001',
  'This request is not awaiting traveler confirmation',
  'retrying a confirmation does not take a second seat'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000d');

select throws_ok(
  $$select public.confirm_join_request(
    (select id from ids where name = 'second_request'), true
  )$$,
  'P0001',
  'This trip no longer has an open seat',
  'a later confirmation cannot exceed capacity'
);

-- Group chat membership.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select is(
  (select count(*)::integer from public.my_trip_conversations()),
  1,
  'confirmation opens a conversation for the traveler'
);
select lives_ok(
  $$insert into ids
    select 'conversation', conversation_id from public.my_trip_conversations()$$,
  'the traveler can see the conversation id'
);
select lives_ok(
  $$select * from public.send_chat_message_v2(
    (select id from ids where name = 'conversation'), 'Hello group', 'client-1'
  )$$,
  'a member can send a message'
);
select lives_ok(
  $$select * from public.send_chat_message_v2(
    (select id from ids where name = 'conversation'), 'Hello group', 'client-1'
  )$$,
  'a member can retry the same client message'
);
select is(
  (select count(*)::integer from public.chat_messages
   where client_id = 'client-1'),
  1,
  'retrying a client message does not duplicate it'
);

select is(
  (select count(*)::integer from public.list_chat_messages(
    (select id from ids where name = 'conversation')
  )),
  2,
  'a member can page through the system event and message'
);
select lives_ok(
  $$select public.mark_conversation_read_through(
    (select id from ids where name = 'conversation')
  )$$,
  'a member can mark the conversation read'
);

-- now() is frozen inside this transaction, so backdate the read position.
select pg_temp.act_as_system();
update public.conversation_members
set last_read_at = now() - interval '1 hour'
where user_id = '00000000-0000-0000-0000-00000000000a';

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select is(
  (select unread_count from public.my_trip_conversations()),
  2,
  'the host sees unread messages from the group'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000c');

select is_empty(
  $$select id from public.chat_messages$$,
  'a non-member cannot read messages'
);
select is_empty(
  $$select id from public.trip_conversations$$,
  'a non-member cannot read conversations'
);
select throws_ok(
  $$select * from public.send_chat_message_v2(
    (select id from ids where name = 'conversation'), 'Let me in', 'client-2'
  )$$,
  'P0001',
  null,
  'a non-member cannot send a message'
);
select throws_ok(
  $$select public.send_chat_message(
    (select id from ids where name = 'conversation'), 'Let me in'
  )$$,
  '42501',
  null,
  'the original send function is no longer callable'
);
select throws_ok(
  $$select * from public.list_chat_messages(
    (select id from ids where name = 'conversation')
  )$$,
  'P0001',
  'Only confirmed group members can read this conversation',
  'a non-member cannot page through messages'
);
select is_empty(
  $$select trip_id from public.trip_logistics$$,
  'a non-member cannot read logistics'
);

-- Logistics.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select throws_ok(
  $$select public.save_trip_logistics(
    (select id from ids where name = 'trip'),
    1, 1, null, null, null, null, null
  )$$,
  'P0001',
  'Only this trip host can update logistics',
  'a confirmed traveler cannot change costs or booking links'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select lives_ok(
  $$select public.save_trip_logistics(
    (select id from ids where name = 'trip'),
    900, 300, 'Riad', 'https://example.com/riad', null, null, 'Book early'
  )$$,
  'the host can save logistics'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select is(
  (select accommodation_name from public.trip_logistics
   where trip_id = (select id from ids where name = 'trip')),
  'Riad',
  'a confirmed traveler can read logistics'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select throws_ok(
  $$select public.save_trip_logistics(
    (select id from ids where name = 'trip'),
    1, 1, 'Riad', 'javascript:alert(1)', null, null, null
  )$$,
  'P0001',
  'Booking links must be valid HTTP or HTTPS URLs',
  'booking links reject non-web URLs'
);

-- Blocking.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000f');

select lives_ok(
  $$select public.block_user('00000000-0000-0000-0000-00000000000a')$$,
  'a user can block a host'
);
select is_empty(
  $$select id from public.trips
    where id = (select id from ids where name = 'trip')$$,
  'a blocked pair cannot see each other''s trips'
);
select throws_ok(
  $$select public.create_join_request(
    (select id from ids where name = 'trip'),
    'I would love to join this route with you.'
  )$$,
  'P0001',
  null,
  'a blocked pair cannot create a join request'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select is_empty(
  $$select id from public.profiles
    where id = '00000000-0000-0000-0000-00000000000f'$$,
  'blocking hides profiles in both directions'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000c');

select is(
  public.is_user_blocked_between(
    '00000000-0000-0000-0000-00000000000a',
    '00000000-0000-0000-0000-00000000000f'
  ),
  false,
  'the block helper reveals nothing about other accounts'
);
select throws_ok(
  $$select * from public.user_blocks$$,
  '42501',
  null,
  'authenticated users cannot read the block table'
);

-- Reports, analytics, and operator-only surfaces.

select lives_ok(
  $$select public.submit_safety_report(
    '00000000-0000-0000-0000-00000000000a',
    (select id from ids where name = 'trip'),
    'spam',
    'This listing looks like spam to me.'
  )$$,
  'a user can submit a report'
);
select is(
  (select count(*)::integer from public.my_safety_reports()),
  1,
  'the reporter can see their report status'
);
select lives_ok(
  $$select public.track_product_event('profile_completed', null, '{}'::jsonb)$$,
  'analytics accepts a known event'
);
select lives_ok(
  $$select public.submit_beta_feedback('discovery', 5::smallint, 'Felt clear.')$$,
  'a user can submit beta feedback'
);
select throws_ok(
  $$truncate public.trips cascade$$,
  '42501',
  null,
  'authenticated users cannot truncate tables'
);
select throws_ok(
  $$select * from public.safety_reports$$,
  '42501',
  null,
  'authenticated users cannot read reports'
);
select throws_ok(
  $$select * from public.analytics_events$$,
  '42501',
  null,
  'authenticated users cannot read analytics'
);
select throws_ok(
  $$select public.track_product_event('made_up_event', null, '{}'::jsonb)$$,
  'P0001',
  'Unsupported product event',
  'analytics rejects unknown events'
);
select throws_ok(
  $$select public.track_product_event('profile_completed', null, '[]'::jsonb)$$,
  'P0001',
  'Event properties must be a small JSON object',
  'analytics rejects non-object properties'
);
select throws_ok(
  $$select * from public.moderation_report_queue$$,
  '42501',
  null,
  'authenticated users cannot read the moderation queue'
);
select throws_ok(
  $$select public.seed_controlled_beta_trips(
    '00000000-0000-0000-0000-00000000000c', 'staging'
  )$$,
  '42501',
  null,
  'authenticated users cannot run the beta seed'
);
select throws_ok(
  $$select public.capture_poc_validation_snapshot(true, true, 0, 'forged')$$,
  '42501',
  null,
  'authenticated users cannot capture a validation snapshot'
);

select pg_temp.act_as_system();

select is(
  (select count(*)::integer from public.analytics_events
   where actor_id = '00000000-0000-0000-0000-00000000000c'),
  1,
  'analytics events are attributed to the signed-in user'
);

set local role anon;

select throws_ok(
  $$select public.create_trip(
    'Anonymous trip', 'Rabat', current_date + 10, current_date + 12,
    '[]'::jsonb, 3::smallint, 100, 100, 'MAD', 'Culture',
    'A summary that is long enough to pass.'
  )$$,
  '42501',
  null,
  'anonymous callers cannot reach the RPCs'
);
select throws_ok(
  $$select id from public.profiles$$,
  '42501',
  null,
  'anonymous callers cannot read profiles'
);

set local role service_role;

select lives_ok(
  $$select * from public.beta_kpi_dashboard$$,
  'the service role can read the KPI dashboard'
);
select lives_ok(
  $$select * from public.poc_evidence_dashboard$$,
  'the service role can read the PoC evidence'
);
select lives_ok(
  $$select * from public.moderation_report_queue$$,
  'the service role can read the moderation queue'
);
select lives_ok(
  $$select public.capture_poc_validation_snapshot(false, false, 1, 'not ready')$$,
  'the service role can capture a snapshot'
);
select throws_ok(
  $$update public.poc_validation_snapshots set note = 'edited'$$,
  '42501',
  null,
  'snapshots cannot be edited'
);
select throws_ok(
  $$delete from public.poc_validation_snapshots$$,
  '42501',
  null,
  'snapshots cannot be deleted'
);

reset role;

select * from finish();

rollback;
