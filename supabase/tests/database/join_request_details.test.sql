-- Declared join details reach the host and go through the same rules.
begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

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
  ('00000000-0000-4000-8000-0000000000f1', 'host@example.test'),
  ('00000000-0000-4000-8000-0000000000f2', 'traveler@example.test');

update public.profiles
set display_name = 'Member',
    onboarding_completed_at = now(),
    linkedin_verified_at = now()
where id in (
  '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000f2'
);

insert into public.trips (
  id, host_id, title, origin_city, destination_city, start_date, end_date, capacity,
  confirmed_traveler_count, lodging_total, transport_total, currency,
  travel_style, summary
)
values (
  '00000000-0000-4000-8000-0000000000f9',
  '00000000-0000-4000-8000-0000000000f1',
  'Atlas loop', 'Rabat', 'Merzouga', current_date + 30, current_date + 33, 4,
  0, 100, 100, 'MAD', 'Culture',
  'A summary that is long enough for the constraint.'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000f1');

select throws_ok(
  $$ select public.create_join_request(
       '00000000-0000-4000-8000-0000000000f9',
       'I would love to join this trip with you all.',
       true, true, true
     ) $$,
  null,
  null,
  'a host still cannot request their own trip'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000f2');

select lives_ok(
  $$ select public.create_join_request(
       '00000000-0000-4000-8000-0000000000f9',
       'I would love to join this trip with you all.',
       true, false, true
     ) $$,
  'a traveler can declare details with a request'
);

select throws_ok(
  $$ update public.trip_join_requests set can_share_driving = false $$,
  '42501',
  null,
  'details cannot be edited directly'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000f1');

select results_eq(
  $$ select available_all_dates, budget_fits, can_share_driving
     from public.trip_join_requests
     where trip_id = '00000000-0000-4000-8000-0000000000f9' $$,
  $$ values (true, false, true) $$,
  'the host reads the declared details'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000f2');

select throws_ok(
  $$ select public.create_join_request(
       '00000000-0000-4000-8000-0000000000f9',
       'I would love to join this trip with you all.',
       true, true, true
     ) $$,
  null,
  null,
  'a second active request is still refused'
);

select * from finish();
rollback;
