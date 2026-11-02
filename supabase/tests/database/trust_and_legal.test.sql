-- Trust details, terms acceptance, and account deletion. Everything rolls back.
begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

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

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000b1', 'host@example.test'),
  ('00000000-0000-4000-8000-0000000000b2', 'traveler@example.test'),
  ('00000000-0000-4000-8000-0000000000b3', 'other@example.test');

update public.profiles
set display_name = 'Host B',
    onboarding_completed_at = now(),
    linkedin_verified_at = now()
where id = '00000000-0000-4000-8000-0000000000b1';

update public.profiles
set display_name = 'Traveler B',
    onboarding_completed_at = now(),
    linkedin_verified_at = now()
where id = '00000000-0000-4000-8000-0000000000b2';

insert into public.trips (
  id, host_id, title, origin_city, destination_city, start_date, end_date, capacity,
  confirmed_traveler_count, lodging_total, transport_total, currency,
  travel_style, summary
)
values (
  '00000000-0000-4000-8000-0000000000c1',
  '00000000-0000-4000-8000-0000000000b1',
  'Atlas loop',
  'Rabat',
  'Merzouga',
  current_date + 30,
  current_date + 33,
  4,
  1,
  100,
  100,
  'MAD',
  'Culture',
  'A summary that is long enough for the constraint.'
);

insert into public.trip_join_requests (id, trip_id, traveler_id, message, status)
values (
  '00000000-0000-4000-8000-0000000000d1',
  '00000000-0000-4000-8000-0000000000c1',
  '00000000-0000-4000-8000-0000000000b2',
  'I would be a considerate and punctual travel companion.',
  'confirmed'
);

insert into public.safety_reports (reporter_id, subject_user_id, reason, details)
values (
  '00000000-0000-4000-8000-0000000000b1',
  '00000000-0000-4000-8000-0000000000b2',
  'spam',
  'A report that is long enough.'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');

-- Trust details
select lives_ok(
  $$ select public.complete_profile(
       'Traveler B', 'Bio', 'Fes', '{}', '{}', null, '@Sam.Travels', ' Nurse '
     ) $$,
  'a user can save an Instagram handle and occupation'
);

select is(
  (select instagram_handle from public.profiles
   where id = '00000000-0000-4000-8000-0000000000b2'),
  'sam.travels',
  'the Instagram handle is normalized'
);

select is(
  (select occupation from public.profiles
   where id = '00000000-0000-4000-8000-0000000000b2'),
  'Nurse',
  'the occupation is trimmed'
);

select throws_ok(
  $$ select public.complete_profile(
       'Traveler B', 'Bio', 'Fes', '{}', '{}', null, 'not a handle!', null
     ) $$,
  'P0001',
  'Enter a valid Instagram username',
  'an invalid Instagram handle is refused'
);

select lives_ok(
  $$ select public.complete_profile('Traveler B', 'Bio', 'Fes', '{}', '{}') $$,
  'trust details are optional'
);

select is(
  (select instagram_handle from public.profiles
   where id = '00000000-0000-4000-8000-0000000000b2'),
  null,
  'leaving the handle empty clears it'
);

-- Terms
select lives_ok(
  $$ select public.accept_terms('2026-11-draft') $$,
  'a user can accept the terms'
);

select is(
  (select terms_version from public.profiles
   where id = '00000000-0000-4000-8000-0000000000b2'),
  '2026-11-draft',
  'the accepted version is recorded'
);

select ok(
  (select terms_accepted_at is not null from public.profiles
   where id = '00000000-0000-4000-8000-0000000000b2'),
  'the acceptance time is recorded'
);

-- Trust facts
select is(
  (select trips_hosted from public.member_trust_facts(
     '00000000-0000-4000-8000-0000000000b1')),
  1,
  'hosted trips are counted'
);

select is(
  (select trips_joined from public.member_trust_facts(
     '00000000-0000-4000-8000-0000000000b2')),
  1,
  'joined trips are counted'
);

reset role;
insert into public.user_blocks (blocker_id, blocked_user_id) values (
  '00000000-0000-4000-8000-0000000000b3',
  '00000000-0000-4000-8000-0000000000b2'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');

select is(
  (select count(*)::integer from public.member_trust_facts(
     '00000000-0000-4000-8000-0000000000b3')),
  0,
  'blocked members see no trust facts'
);

-- Account deletion
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');

select throws_ok(
  $$ select public.delete_my_account() $$,
  'P0001',
  'Cancel your upcoming trips with confirmed travelers before deleting your account',
  'a host with a confirmed group must cancel first'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');

reset role;
insert into public.trip_conversations (id, trip_id) values (
  '00000000-0000-4000-8000-0000000000e1',
  '00000000-0000-4000-8000-0000000000c1'
) on conflict (trip_id) do nothing;
insert into public.chat_messages (conversation_id, sender_id, sender_name, body)
select id, '00000000-0000-4000-8000-0000000000b2', 'Traveler B', 'Hello group'
from public.trip_conversations
where trip_id = '00000000-0000-4000-8000-0000000000c1';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');

select lives_ok(
  $$ select public.delete_my_account() $$,
  'a traveler can delete their account'
);

reset role;

select is(
  (select count(*)::integer from auth.users
   where id = '00000000-0000-4000-8000-0000000000b2'),
  0,
  'the account is gone'
);

select is(
  (select confirmed_traveler_count::integer from public.trips
   where id = '00000000-0000-4000-8000-0000000000c1'),
  0,
  'the seat is released'
);

select is(
  (select count(*)::integer from public.notifications
   where user_id = '00000000-0000-4000-8000-0000000000b1'
     and kind in ('traveler_left', 'traveler_left_late')),
  1,
  'the host is told that the traveler left'
);

select is(
  (select sender_name from public.chat_messages where body = 'Hello group'),
  'Former member',
  'chat messages no longer name the deleted user'
);

select is(
  (select count(*)::integer from public.safety_reports
   where reporter_id = '00000000-0000-4000-8000-0000000000b1'
     and subject_user_id is null),
  1,
  'a report about the deleted user is kept'
);

select * from finish();

rollback;
