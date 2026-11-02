-- Devices that receive push notifications. A token belongs to whoever signed in
-- on that device last, so a shared phone never receives the previous user's alerts.
create table public.push_tokens (
  token text primary key check (char_length(token) between 1 and 4096),
  user_id uuid not null references auth.users (id) on delete cascade,
  updated_at timestamptz not null default now()
);

create index push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;

revoke all on public.push_tokens from anon, authenticated;
grant select, delete on public.push_tokens to service_role;

create or replace function public.register_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  insert into public.push_tokens (token, user_id)
  values (p_token, (select auth.uid()))
  on conflict (token) do update
  set user_id = excluded.user_id,
      updated_at = now();
end;
$$;

revoke all on function public.register_push_token(text)
from public, anon;
grant execute on function public.register_push_token(text)
to authenticated;
