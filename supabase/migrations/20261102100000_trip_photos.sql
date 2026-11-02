-- Hosts can add up to five photos to a trip they host. Files live in a public
-- bucket under the trip id, like avatars live under the user id.
alter table public.trips
add column photo_paths text[] not null default '{}';
alter table public.trips
add constraint trips_photo_paths_limit check (cardinality(photo_paths) <= 5);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'trip-photos',
  'trip-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Comparing as text keeps a malformed folder name from raising a cast error.
create or replace function public.is_trip_photo_folder_host(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trips
    where id::text = p_folder
      and host_id = (select auth.uid())
  );
$$;
revoke all on function public.is_trip_photo_folder_host(text)
from public, anon;
grant execute on function public.is_trip_photo_folder_host(text)
to authenticated;

-- Public URLs serve the files to everyone. Listing and writing stay with the
-- host, and removing a file through the Storage API needs the select policy.
create policy "Hosts can see their trip photos"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'trip-photos'
  and public.is_trip_photo_folder_host((storage.foldername(name))[1])
);

create policy "Hosts can upload trip photos"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'trip-photos'
  and public.is_trip_photo_folder_host((storage.foldername(name))[1])
);

create policy "Hosts can delete trip photos"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'trip-photos'
  and public.is_trip_photo_folder_host((storage.foldername(name))[1])
);

create or replace function public.set_trip_photos(
  p_trip_id uuid,
  p_paths text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  paths text[] := coalesce(p_paths, '{}');
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.trips
    where id = p_trip_id
      and host_id = (select auth.uid())
  ) then
    raise exception 'Only this trip host can change its photos';
  end if;

  if cardinality(paths) > 5 then
    raise exception 'A trip can have up to 5 photos';
  end if;

  if exists (
    select 1
    from unnest(paths) as path
    where path not like p_trip_id::text || '/%'
      or path like '%..%'
  ) then
    raise exception 'Each photo must be stored with this trip';
  end if;

  update public.trips
  set photo_paths = paths
  where id = p_trip_id;
end;
$$;
revoke all on function public.set_trip_photos(uuid, text[])
from public, anon;
grant execute on function public.set_trip_photos(uuid, text[])
to authenticated;
