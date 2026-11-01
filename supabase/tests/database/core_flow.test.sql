-- Trip lifecycle, leaving a trip, and notifications. Everything rolls back.
begin;

create extension if not exists pgtap with schema extensions;

select plan(39);

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

create function pg_temp.new_user(p_id uuid, p_name text)
returns void
language plpgsql
as $$
begin
  insert into auth.users (id, email)
  values (p_id, p_name || '@example.test');

  update public.profiles
  set display_name = p_name,
      onboarding_completed_at = now(),
      linkedin_verified_at = now()
  where id = p_id;
end;
$$;

select pg_temp.new_user('00000000-0000-0000-0000-00000000000a', 'host');
select pg_temp.new_user('00000000-0000-0000-0000-00000000000b', 'traveler');
select pg_temp.new_user('00000000-0000-0000-0000-00000000000c', 'stranger');
select pg_temp.new_user('00000000-0000-0000-0000-00000000000d', 'pending');

create temp table ids (name text primary key, id uuid not null);
grant all on ids to authenticated;

create function pg_temp.edit_trip(p_title text, p_capacity smallint)
returns uuid
language sql
as $$
  select public.update_trip(
    (select id from ids where name = 'trip'),
    p_title, 'Marrakech', current_date + 30, current_date + 33,
    jsonb_build_array(
      jsonb_build_object('city', 'Ait Benhaddou', 'arrival_date', current_date + 31),
      jsonb_build_object('city', 'Merzouga', 'arrival_date', current_date + 33)
    ),
    p_capacity, 700, 300, 'MAD', 'Culture',
    'An updated summary that is long enough to pass.'
  );
$$;

create function pg_temp.kinds(p_user_id uuid)
returns text[]
language sql
as $$
  select coalesce(array_agg(kind order by kind), '{}')
  from public.notifications
  where user_id = p_user_id;
$$;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

insert into ids
select 'trip', public.create_trip(
  'Atlas villages', 'Marrakech', current_date + 30, current_date + 33,
  jsonb_build_array(jsonb_build_object(
    'city', 'Merzouga', 'arrival_date', current_date + 33
  )),
  3::smallint, 600, 300, 'MAD', 'Culture',
  'A summary that is long enough to pass.'
);

-- Notifications follow the approval flow.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

insert into ids
select 'request', public.create_join_request(
  (select id from ids where name = 'trip'),
  'I would love to join this route with you.'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select is(
  (select array_agg(kind) from public.notifications),
  array['join_request_received'],
  'the host is notified of a join request'
);
select is(
  (select actor_name from public.notifications),
  'traveler',
  'the notification names the traveler'
);
select lives_ok(
  $$select public.review_join_request(
    (select id from ids where name = 'request'), true
  )$$,
  'the host approves'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select is(
  (select array_agg(kind) from public.notifications),
  array['request_approved'],
  'the traveler is notified of the approval'
);
select is(
  (select actor_name from public.notifications),
  'host',
  'the notification names the host'
);
select lives_ok(
  $$select public.confirm_join_request(
    (select id from ids where name = 'request'), true
  )$$,
  'the traveler confirms'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select is(
  (select count(*)::integer from public.notifications
   where kind = 'traveler_confirmed'),
  1,
  'the host is notified of the confirmation'
);

-- Notification privacy.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000c');

select is_empty(
  $$select id from public.notifications$$,
  'a user cannot read another user''s notifications'
);
select throws_ok(
  $$insert into public.notifications (user_id, kind, trip_title)
    values ('00000000-0000-0000-0000-00000000000a', 'trip_updated', 'Forged')$$,
  '42501',
  null,
  'a user cannot create notifications directly'
);
select throws_ok(
  $$select public.notify_confirmed_travelers(
    (select trip from public.trips as trip limit 1), 'trip_cancelled'
  )$$,
  '42501',
  null,
  'a user cannot send notifications through the internal function'
);
select lives_ok(
  $$select public.mark_notifications_read()$$,
  'marking read affects only the caller'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select is(
  (select count(*)::integer from public.notifications where read_at is null),
  2,
  'another user marking read leaves the host''s unread count'
);
select lives_ok(
  $$select public.mark_notifications_read(
    (select id from public.notifications
     where kind = 'traveler_confirmed')
  )$$,
  'a host can mark one notification read'
);
select is(
  (select count(*)::integer from public.notifications where read_at is null),
  1,
  'marking one read leaves the other unread'
);
select lives_ok(
  $$select public.mark_notifications_read()$$,
  'a host can mark all notifications read'
);
select is(
  (select count(*)::integer from public.notifications where read_at is null),
  0,
  'all notifications are read'
);

-- Editing.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select throws_ok(
  $$select pg_temp.edit_trip('Hijacked trip', 4::smallint)$$,
  'P0001',
  'Only this trip host can edit the trip',
  'a traveler cannot edit the trip'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select lives_ok(
  $$select pg_temp.edit_trip('Atlas and desert', 4::smallint)$$,
  'the host can edit the trip'
);
select is(
  (select title from public.trips
   where id = (select id from ids where name = 'trip')),
  'Atlas and desert',
  'the edit is saved'
);
select is(
  (select destination_city from public.trips
   where id = (select id from ids where name = 'trip')),
  'Merzouga',
  'the destination follows the last stop'
);
select is(
  (select array_agg(city order by position) from public.trip_stops
   where trip_id = (select id from ids where name = 'trip')),
  array['Ait Benhaddou', 'Merzouga'],
  'the stops are replaced in order'
);
select is(
  (select confirmed_traveler_count from public.trips
   where id = (select id from ids where name = 'trip')),
  1::smallint,
  'editing keeps the confirmed group'
);
select throws_ok(
  $$select pg_temp.edit_trip('Atlas and desert', 1::smallint)$$,
  'P0001',
  'Capacity cannot be lower than the confirmed group',
  'capacity cannot drop below the confirmed group'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select ok(
  'trip_updated' = any(pg_temp.kinds('00000000-0000-0000-0000-00000000000b')),
  'a confirmed traveler is notified of the edit'
);

-- Leaving.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000c');

select throws_ok(
  $$select public.leave_trip((select id from ids where name = 'request'))$$,
  'P0001',
  'Only this traveler can leave the trip',
  'another user cannot make a traveler leave'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select is(
  public.leave_trip((select id from ids where name = 'request')),
  false,
  'leaving 30 days out is not late'
);
select is(
  (select confirmed_traveler_count from public.trips
   where id = (select id from ids where name = 'trip')),
  0::smallint,
  'leaving releases the seat'
);
select is_empty(
  $$select conversation_id from public.my_trip_conversations()$$,
  'leaving removes the traveler from the conversation'
);
select throws_ok(
  $$select public.leave_trip((select id from ids where name = 'request'))$$,
  'P0001',
  'Only a confirmed traveler can leave the trip',
  'a traveler cannot leave twice'
);
select lives_ok(
  $$insert into ids
    select 'rejoin', public.create_join_request(
      (select id from ids where name = 'trip'),
      'I can make these dates after all, if you will have me.'
    )$$,
  'a traveler who left can request again'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select ok(
  'traveler_left' = any(pg_temp.kinds('00000000-0000-0000-0000-00000000000a')),
  'the host is notified when a traveler leaves'
);
select lives_ok(
  $$select public.review_join_request(
    (select id from ids where name = 'rejoin'), true
  )$$,
  'the host approves the returning traveler'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select public.confirm_join_request((select id from ids where name = 'rejoin'), true);

-- Move departure inside the seven-day window.
select set_config('role', 'none', true);
update public.trips
set start_date = current_date + 3,
    end_date = current_date + 6
where id = (select id from ids where name = 'trip');
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');

select is(
  public.leave_trip((select id from ids where name = 'rejoin')),
  true,
  'leaving three days out is late'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select ok(
  'traveler_left_late' = any(pg_temp.kinds('00000000-0000-0000-0000-00000000000a')),
  'the host is told the departure was late'
);

-- Cancelling.

select pg_temp.act_as('00000000-0000-0000-0000-00000000000d');

insert into ids
select 'pending', public.create_join_request(
  (select id from ids where name = 'trip'),
  'I would love to join this route with you.'
);

select throws_ok(
  $$select public.cancel_trip((select id from ids where name = 'trip'))$$,
  'P0001',
  'Only this trip host can cancel the trip',
  'a traveler cannot cancel the trip'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

select lives_ok(
  $$select public.cancel_trip((select id from ids where name = 'trip'))$$,
  'the host can cancel the trip'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000d');

select is(
  (select status from public.trip_join_requests
   where id = (select id from ids where name = 'pending')),
  'declined',
  'a pending request is declined and stays readable after cancelling'
);
select is(
  (select status from public.trips
   where id = (select id from ids where name = 'trip')),
  'cancelled',
  'a traveler with a request can still open the cancelled trip'
);

select pg_temp.act_as('00000000-0000-0000-0000-00000000000c');

select is_empty(
  $$select id from public.trips
    where id = (select id from ids where name = 'trip')$$,
  'a cancelled trip is hidden from everyone else'
);

select * from finish();

rollback;
