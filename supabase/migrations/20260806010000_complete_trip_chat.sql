alter table public.chat_messages
add column client_id text;

alter table public.chat_messages
add constraint chat_messages_client_id_length check (
  client_id is null or char_length(client_id) between 8 and 80
);

create unique index chat_messages_sender_client_id_unique
on public.chat_messages (conversation_id, sender_id, client_id)
where client_id is not null;

create index chat_messages_conversation_history_idx
on public.chat_messages (conversation_id, sent_at desc, id desc);

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_members'
  ) then
    execute 'alter publication supabase_realtime add table public.conversation_members';
  end if;
end;
$$;

create or replace function public.list_chat_messages(
  p_conversation_id uuid,
  p_before_sent_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 40
)
returns table (
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  body text,
  message_type text,
  sent_at timestamptz,
  client_id text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'Only confirmed group members can read this conversation';
  end if;

  if p_limit not between 1 and 100 then
    raise exception 'Message page size must be between 1 and 100';
  end if;

  if (p_before_sent_at is null) <> (p_before_id is null) then
    raise exception 'Both message cursor values are required';
  end if;

  return query
  select
    message.id,
    message.conversation_id,
    message.sender_id,
    message.sender_name,
    message.body,
    message.message_type,
    message.sent_at,
    message.client_id
  from public.chat_messages as message
  where message.conversation_id = p_conversation_id
    and (
      p_before_sent_at is null
      or (message.sent_at, message.id) < (p_before_sent_at, p_before_id)
    )
  order by message.sent_at desc, message.id desc
  limit p_limit;
end;
$$;

create or replace function public.send_chat_message_v2(
  p_conversation_id uuid,
  p_body text,
  p_client_id text
)
returns table (
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  body text,
  message_type text,
  sent_at timestamptz,
  client_id text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  sender_display_name text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'Only confirmed group members can send messages';
  end if;

  if p_body is null
    or char_length(trim(p_body)) not between 1 and 1000 then
    raise exception 'Messages must contain 1 to 1000 characters';
  end if;

  if p_client_id is null
    or char_length(trim(p_client_id)) not between 8 and 80 then
    raise exception 'A valid client message identifier is required';
  end if;

  select coalesce(profile.display_name, 'CoTravel member')
  into sender_display_name
  from public.profiles as profile
  where profile.id = (select auth.uid());

  return query
  insert into public.chat_messages as message (
    conversation_id,
    sender_id,
    sender_name,
    body,
    client_id
  )
  values (
    p_conversation_id,
    (select auth.uid()),
    coalesce(sender_display_name, 'CoTravel member'),
    trim(p_body),
    trim(p_client_id)
  )
  on conflict (conversation_id, sender_id, client_id)
  where client_id is not null
  do update set client_id = excluded.client_id
  returning
    message.id,
    message.conversation_id,
    message.sender_id,
    message.sender_name,
    message.body,
    message.message_type,
    message.sent_at,
    message.client_id;

  update public.conversation_members as membership
  set last_read_at = now()
  where membership.conversation_id = p_conversation_id
    and membership.user_id = (select auth.uid());
end;
$$;

create or replace function public.mark_conversation_read_through(
  p_conversation_id uuid,
  p_read_through timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  effective_read_at timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  effective_read_at := least(coalesce(p_read_through, now()), now());

  update public.conversation_members as membership
  set last_read_at = greatest(membership.last_read_at, effective_read_at)
  where membership.conversation_id = p_conversation_id
    and membership.user_id = (select auth.uid());

  if not found then
    raise exception 'Only confirmed group members can read this conversation';
  end if;
end;
$$;

revoke all on function public.list_chat_messages(
  uuid,
  timestamptz,
  uuid,
  integer
) from public;
grant execute on function public.list_chat_messages(
  uuid,
  timestamptz,
  uuid,
  integer
) to authenticated;

revoke all on function public.send_chat_message_v2(uuid, text, text)
from public;
grant execute on function public.send_chat_message_v2(uuid, text, text)
to authenticated;

revoke all on function public.mark_conversation_read_through(
  uuid,
  timestamptz
) from public;
grant execute on function public.mark_conversation_read_through(
  uuid,
  timestamptz
) to authenticated;
