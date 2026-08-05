create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  bio text,
  home_city text,
  avatar_path text,
  travel_styles text[] not null default '{}',
  languages text[] not null default '{}',
  linkedin_verified_at timestamptz,
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (
    display_name is null or char_length(display_name) between 2 and 60
  ),
  constraint profiles_bio_length check (
    bio is null or char_length(bio) <= 280
  ),
  constraint profiles_home_city_length check (
    home_city is null or char_length(home_city) <= 80
  ),
  constraint profiles_travel_styles_limit check (
    cardinality(travel_styles) <= 5
  ),
  constraint profiles_languages_limit check (
    cardinality(languages) <= 8
  )
);

alter table public.profiles enable row level security;

grant select, insert, update on public.profiles to authenticated;

create policy "Authenticated users can read completed profiles"
on public.profiles
for select
to authenticated
using (
  onboarding_completed_at is not null
  or id = (select auth.uid())
);

create policy "Users can create their own profile"
on public.profiles
for insert
to authenticated
with check (id = (select auth.uid()));

create policy "Users can update their own profile"
on public.profiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (id)
select id from auth.users
on conflict (id) do nothing;

create or replace function public.sync_my_linkedin_verification()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  is_verified boolean;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select exists (
    select 1
    from auth.identities
    where user_id = (select auth.uid())
      and provider = 'linkedin_oidc'
  ) into is_verified;

  update public.profiles
  set linkedin_verified_at = case
    when is_verified then coalesce(linkedin_verified_at, now())
    else null
  end
  where id = (select auth.uid());

  return is_verified;
end;
$$;

revoke all on function public.sync_my_linkedin_verification() from public;
grant execute on function public.sync_my_linkedin_verification() to authenticated;

create or replace function public.complete_profile(
  p_display_name text,
  p_bio text,
  p_home_city text,
  p_travel_styles text[],
  p_languages text[],
  p_avatar_path text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  completed_profile public.profiles;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if char_length(trim(p_display_name)) not between 2 and 60 then
    raise exception 'Display name must contain 2 to 60 characters';
  end if;

  if char_length(trim(p_bio)) > 280 then
    raise exception 'Bio must not exceed 280 characters';
  end if;

  if char_length(trim(p_home_city)) > 80 then
    raise exception 'Home city must not exceed 80 characters';
  end if;

  if cardinality(coalesce(p_travel_styles, '{}')) > 5 then
    raise exception 'Choose no more than 5 travel styles';
  end if;

  if cardinality(coalesce(p_languages, '{}')) > 8 then
    raise exception 'Choose no more than 8 languages';
  end if;

  insert into public.profiles (
    id,
    display_name,
    bio,
    home_city,
    travel_styles,
    languages,
    avatar_path,
    onboarding_completed_at
  )
  values (
    (select auth.uid()),
    trim(p_display_name),
    nullif(trim(p_bio), ''),
    nullif(trim(p_home_city), ''),
    coalesce(p_travel_styles, '{}'),
    coalesce(p_languages, '{}'),
    p_avatar_path,
    now()
  )
  on conflict (id) do update set
    display_name = excluded.display_name,
    bio = excluded.bio,
    home_city = excluded.home_city,
    travel_styles = excluded.travel_styles,
    languages = excluded.languages,
    avatar_path = coalesce(excluded.avatar_path, public.profiles.avatar_path),
    onboarding_completed_at = coalesce(
      public.profiles.onboarding_completed_at,
      excluded.onboarding_completed_at
    )
  returning * into completed_profile;

  return completed_profile;
end;
$$;

revoke all on function public.complete_profile(
  text,
  text,
  text,
  text[],
  text[],
  text
) from public;
grant execute on function public.complete_profile(
  text,
  text,
  text,
  text[],
  text[],
  text
) to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatars',
  'avatars',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Avatar images are publicly readable"
on storage.objects
for select
using (bucket_id = 'avatars');

create policy "Users can upload their own avatar"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Users can update their own avatar"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Users can delete their own avatar"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
