-- Only a trip's host can change its photos. Everything rolls back.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

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
  ('00000000-0000-4000-8000-0000000000f1', 'photo-host@example.test'),
  ('00000000-0000-4000-8000-0000000000f2', 'photo-other@example.test');

insert into public.trips (
  id, host_id, title, origin_city, destination_city, start_date, end_date, capacity,
  confirmed_traveler_count, lodging_total, transport_total, currency,
  travel_style, summary, status
)
values (
  '00000000-0000-4000-8000-0000000000f9',
  '00000000-0000-4000-8000-0000000000f1',
  'Photo loop', 'Rabat', 'Merzouga', current_date + 30, current_date + 33, 4,
  0, 100, 100, 'MAD', 'Culture',
  'A summary that is long enough for the constraint.', 'published'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000f1');

select lives_ok(
  $$ select public.set_trip_photos(
       '00000000-0000-4000-8000-0000000000f9',
       array[
         '00000000-0000-4000-8000-0000000000f9/one.jpg',
         '00000000-0000-4000-8000-0000000000f9/two.jpg'
       ]
     ) $$,
  'the host can set photos stored under the trip'
);

select is(
  (select photo_paths from public.trips
   where id = '00000000-0000-4000-8000-0000000000f9'),
  array[
    '00000000-0000-4000-8000-0000000000f9/one.jpg',
    '00000000-0000-4000-8000-0000000000f9/two.jpg'
  ],
  'the photos are saved in order'
);

select throws_ok(
  $$ select public.set_trip_photos(
       '00000000-0000-4000-8000-0000000000f9',
       array['00000000-0000-4000-8000-0000000000f1/avatar.jpg']
     ) $$,
  'Each photo must be stored with this trip',
  'a photo from another folder is refused'
);

select throws_ok(
  $$ select public.set_trip_photos(
       '00000000-0000-4000-8000-0000000000f9',
       array['00000000-0000-4000-8000-0000000000f9/../x.jpg']
     ) $$,
  'Each photo must be stored with this trip',
  'a path that climbs out of the folder is refused'
);

select throws_ok(
  $$ select public.set_trip_photos(
       '00000000-0000-4000-8000-0000000000f9',
       array(
         select '00000000-0000-4000-8000-0000000000f9/' || n || '.jpg'
         from generate_series(1, 6) as n
       )
     ) $$,
  'A trip can have up to 5 photos',
  'six photos are refused'
);

select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('trip-photos', '00000000-0000-4000-8000-0000000000f9/three.jpg') $$,
  'the host can upload into the trip folder'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000f2');

select throws_ok(
  $$ select public.set_trip_photos(
       '00000000-0000-4000-8000-0000000000f9',
       '{}'
     ) $$,
  'Only this trip host can change its photos',
  'another member cannot change the photos'
);

select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('trip-photos', '00000000-0000-4000-8000-0000000000f9/intruder.jpg') $$,
  '42501',
  null,
  'another member cannot upload into the trip folder'
);

select is(
  (select count(*)::int from storage.objects
   where bucket_id = 'trip-photos'),
  0,
  'another member cannot list the trip photos'
);

select * from finish();
rollback;
