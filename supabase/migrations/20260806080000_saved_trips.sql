-- Trips a member bookmarked. The list is private to its owner, and a trip that
-- becomes invisible, such as after a block, drops out through the trips policy.
create table public.saved_trips (
  user_id uuid not null references auth.users (id) on delete cascade,
  trip_id uuid not null references public.trips (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, trip_id)
);

create index saved_trips_trip_idx on public.saved_trips (trip_id);

alter table public.saved_trips enable row level security;

revoke all on public.saved_trips from anon, authenticated;
grant select, insert, delete on public.saved_trips to authenticated;

create policy "Members read their saved trips"
on public.saved_trips
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Members save trips they can see"
on public.saved_trips
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.trips where trips.id = saved_trips.trip_id)
);

create policy "Members remove their saved trips"
on public.saved_trips
for delete
to authenticated
using (user_id = (select auth.uid()));
