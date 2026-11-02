-- Crash reports. Readable only with the service role, and not tied to an account.
create table public.client_errors (
  id bigint generated always as identity primary key,
  kind text not null check (char_length(kind) between 1 and 200),
  stack text not null check (char_length(stack) <= 4000),
  app_version text not null check (char_length(app_version) between 1 and 40),
  platform text not null check (char_length(platform) between 1 and 40),
  created_at timestamptz not null default now()
);

create index client_errors_recent_idx on public.client_errors (created_at desc);

alter table public.client_errors enable row level security;

revoke all on public.client_errors from anon, authenticated;
grant select, delete on public.client_errors to service_role;

create or replace function public.report_client_error(
  p_kind text,
  p_stack text,
  p_app_version text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  insert into public.client_errors (kind, stack, app_version, platform)
  values (p_kind, p_stack, p_app_version, p_platform);
end;
$$;

revoke all on function public.report_client_error(text, text, text, text)
from public, anon;
grant execute on function public.report_client_error(text, text, text, text)
to authenticated;

-- The language a device's push notifications are written in.
alter table public.push_tokens
  add column language text not null default 'en'
  check (language in ('en', 'fr'));

create or replace function public.register_push_token(
  p_token text,
  p_language text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  insert into public.push_tokens (token, user_id, language)
  values (p_token, (select auth.uid()), p_language)
  on conflict (token) do update
  set user_id = excluded.user_id,
      language = excluded.language,
      updated_at = now();
end;
$$;

revoke all on function public.register_push_token(text, text)
from public, anon;
grant execute on function public.register_push_token(text, text)
to authenticated;
