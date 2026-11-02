-- Saved trips stay private and follow trip visibility. Everything rolls back.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

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
  ('00000000-0000-4000-8000-0000000000d1', 'host@example.test'),
  ('00000000-0000-4000-8000-0000000000d2', 'saver@example.test'),
  ('00000000-0000-4000-8000-0000000000d3', 'other@example.test');

insert into public.trips (
  id, host_id, title, origin_city, destination_city, start_date, end_date, capacity,
  confirmed_traveler_count, lodging_total, transport_total, currency,
  travel_style, summary, status
)
values
  (
    '00000000-0000-4000-8000-0000000000e1',
    '00000000-0000-4000-8000-0000000000d1',
    'Open loop', 'Rabat', 'Merzouga', current_date + 30, current_date + 33, 4,
    0, 100, 100, 'MAD', 'Culture',
    'A summary that is long enough for the constraint.', 'published'
  ),
  (
    '00000000-0000-4000-8000-0000000000e2',
    '00000000-0000-4000-8000-0000000000d1',
    'Cancelled loop', 'Rabat', 'Merzouga', current_date + 30, current_date + 33, 4,
    0, 100, 100, 'MAD', 'Culture',
    'A summary that is long enough for the constraint.', 'cancelled'
  );

select pg_temp.act_as('00000000-0000-4000-8000-0000000000d2');

select lives_ok(
  $$ insert into public.saved_trips (user_id, trip_id) values
     ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000e1') $$,
  'a member can save a trip they can see'
);

select lives_ok(
  $$ insert into public.saved_trips (user_id, trip_id) values
     ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000e1')
     on conflict do nothing $$,
  'saving the same trip twice is harmless'
);

select throws_ok(
  $$ insert into public.saved_trips (user_id, trip_id) values
     ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000e2') $$,
  '42501',
  null,
  'a trip the member cannot see cannot be saved'
);

select throws_ok(
  $$ insert into public.saved_trips (user_id, trip_id) values
     ('00000000-0000-4000-8000-0000000000d3', '00000000-0000-4000-8000-0000000000e1') $$,
  '42501',
  null,
  'nobody can save a trip for someone else'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000d3');

select is(
  (select count(*)::int from public.saved_trips),
  0,
  'another member cannot read the list'
);

delete from public.saved_trips
where user_id = '00000000-0000-4000-8000-0000000000d2';

select pg_temp.act_as('00000000-0000-4000-8000-0000000000d2');

select is(
  (select count(*)::int from public.saved_trips),
  1,
  'another member cannot delete from the list'
);

select lives_ok(
  $$ delete from public.saved_trips
     where trip_id = '00000000-0000-4000-8000-0000000000e1' $$,
  'the owner can remove a saved trip'
);

select is(
  (select count(*)::int from public.saved_trips),
  0,
  'the removal took effect'
);

select * from finish();
rollback;
