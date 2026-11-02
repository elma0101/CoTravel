-- Only a trip's host can set its departure point, and renaming the departure
-- drops a point that no longer matches. Everything rolls back.
begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

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
  ('00000000-0000-4000-8000-0000000000e1', 'origin-host@example.test'),
  ('00000000-0000-4000-8000-0000000000e2', 'origin-other@example.test');

insert into public.trips (
  id, host_id, title, origin_city, destination_city, start_date, end_date, capacity,
  confirmed_traveler_count, lodging_total, transport_total, currency,
  travel_style, summary, status
)
values (
  '00000000-0000-4000-8000-0000000000e9',
  '00000000-0000-4000-8000-0000000000e1',
  'Station start', 'Casa Voyageurs, Casablanca', 'Merzouga',
  current_date + 30, current_date + 33, 4,
  0, 100, 100, 'MAD', 'Culture',
  'A summary that is long enough for the constraint.', 'published'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');

select lives_ok(
  $$ select public.set_trip_origin_point(
       '00000000-0000-4000-8000-0000000000e9', 33.5902, -7.5900
     ) $$,
  'the host can set the departure point'
);

select is(
  (select array[origin_latitude, origin_longitude] from public.trips
   where id = '00000000-0000-4000-8000-0000000000e9'),
  array[33.5902, -7.5900]::double precision[],
  'the departure point is saved'
);

select throws_ok(
  $$ select public.set_trip_origin_point(
       '00000000-0000-4000-8000-0000000000e9', 33.5902, null
     ) $$,
  'Choose a valid departure point',
  'half a point is refused'
);

select throws_ok(
  $$ select public.set_trip_origin_point(
       '00000000-0000-4000-8000-0000000000e9', 120, -7.59
     ) $$,
  'Choose a valid departure point',
  'a latitude out of range is refused'
);

reset role;

update public.trips
set title = 'Station start again'
where id = '00000000-0000-4000-8000-0000000000e9';

update public.trips
set origin_city = 'Casa Voyageurs, Casablanca'
where id = '00000000-0000-4000-8000-0000000000e9';

select isnt(
  (select origin_latitude from public.trips
   where id = '00000000-0000-4000-8000-0000000000e9'),
  null,
  'saving the same departure keeps the point'
);

update public.trips
set origin_city = 'Rabat'
where id = '00000000-0000-4000-8000-0000000000e9';

select is(
  (select origin_latitude from public.trips
   where id = '00000000-0000-4000-8000-0000000000e9'),
  null,
  'a renamed departure drops the old point'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000e2');

select throws_ok(
  $$ select public.set_trip_origin_point(
       '00000000-0000-4000-8000-0000000000e9', 34.02, -6.84
     ) $$,
  'Only this trip host can edit the trip',
  'another member cannot set the departure point'
);

select * from finish();
rollback;
