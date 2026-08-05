create table public.trip_conversations (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null unique references public.trips (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.trip_conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.trip_conversations (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null,
  sender_name text,
  body text not null,
  message_type text not null default 'member',
  sent_at timestamptz not null default now(),
  constraint chat_messages_body_length check (char_length(body) between 1 and 1000),
  constraint chat_messages_type_valid check (
    message_type in ('member', 'system')
  ),
  constraint chat_messages_sender_valid check (
    (message_type = 'system' and sender_id is null)
    or (message_type = 'member' and sender_id is not null)
  )
);

create index conversation_members_user_idx
on public.conversation_members (user_id, joined_at desc);

create index chat_messages_conversation_sent_idx
on public.chat_messages (conversation_id, sent_at);

alter table public.trip_conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.chat_messages enable row level security;

grant select on public.trip_conversations to authenticated;
grant select on public.conversation_members to authenticated;
grant select on public.chat_messages to authenticated;

create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members
    where conversation_id = p_conversation_id
      and user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_conversation_member(uuid) from public;
grant execute on function public.is_conversation_member(uuid) to authenticated;

create policy "Members can read their trip conversations"
on public.trip_conversations
for select
to authenticated
using (public.is_conversation_member(id));

create policy "Members can read conversation membership"
on public.conversation_members
for select
to authenticated
using (public.is_conversation_member(conversation_id));

create policy "Members can read chat messages"
on public.chat_messages
for select
to authenticated
using (public.is_conversation_member(conversation_id));

create or replace function public.open_chat_after_trip_confirmation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  conversation_id uuid;
  trip_host_id uuid;
  traveler_name text;
begin
  if new.status <> 'confirmed' or old.status = 'confirmed' then
    return new;
  end if;

  select host_id
  into trip_host_id
  from public.trips
  where id = new.trip_id;

  select coalesce(display_name, 'A traveler')
  into traveler_name
  from public.profiles
  where id = new.traveler_id;

  insert into public.trip_conversations (trip_id)
  values (new.trip_id)
  on conflict (trip_id) do update set trip_id = excluded.trip_id
  returning id into conversation_id;

  insert into public.conversation_members (conversation_id, user_id)
  values
    (conversation_id, trip_host_id),
    (conversation_id, new.traveler_id)
  on conflict (conversation_id, user_id) do nothing;

  insert into public.chat_messages (
    conversation_id,
    sender_id,
    sender_name,
    body,
    message_type
  )
  values (
    conversation_id,
    null,
    null,
    traveler_name || ' confirmed their place. The trip chat is now open.',
    'system'
  );

  return new;
end;
$$;

create trigger trip_join_request_opens_chat
after update of status on public.trip_join_requests
for each row execute function public.open_chat_after_trip_confirmation();

revoke all on function public.open_chat_after_trip_confirmation() from public;

insert into public.trip_conversations (trip_id)
select distinct trip_id
from public.trip_join_requests
where status = 'confirmed'
on conflict (trip_id) do nothing;

insert into public.conversation_members (conversation_id, user_id)
select conversation.id, trip.host_id
from public.trip_conversations as conversation
join public.trips as trip on trip.id = conversation.trip_id
on conflict (conversation_id, user_id) do nothing;

insert into public.conversation_members (conversation_id, user_id)
select conversation.id, request.traveler_id
from public.trip_conversations as conversation
join public.trip_join_requests as request
  on request.trip_id = conversation.trip_id
where request.status = 'confirmed'
on conflict (conversation_id, user_id) do nothing;

create or replace function public.my_trip_conversations()
returns table (
  conversation_id uuid,
  trip_id uuid,
  trip_title text,
  origin_city text,
  destination_city text,
  member_count integer,
  last_message text,
  last_message_at timestamptz,
  unread_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    conversation.id,
    trip.id,
    trip.title,
    trip.origin_city,
    trip.destination_city,
    (
      select count(*)::integer
      from public.conversation_members as all_members
      where all_members.conversation_id = conversation.id
    ),
    latest.body,
    latest.sent_at,
    (
      select count(*)::integer
      from public.chat_messages as unread
      where unread.conversation_id = conversation.id
        and unread.sent_at > membership.last_read_at
        and unread.sender_id is distinct from (select auth.uid())
    )
  from public.conversation_members as membership
  join public.trip_conversations as conversation
    on conversation.id = membership.conversation_id
  join public.trips as trip on trip.id = conversation.trip_id
  left join lateral (
    select message.body, message.sent_at
    from public.chat_messages as message
    where message.conversation_id = conversation.id
    order by message.sent_at desc
    limit 1
  ) as latest on true
  where membership.user_id = (select auth.uid())
  order by latest.sent_at desc nulls last, conversation.created_at desc;
$$;

create or replace function public.send_chat_message(
  p_conversation_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  sender_display_name text;
  created_message_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'Only confirmed group members can send messages';
  end if;

  if char_length(trim(p_body)) not between 1 and 1000 then
    raise exception 'Messages must contain 1 to 1000 characters';
  end if;

  select coalesce(display_name, 'CoTravel member')
  into sender_display_name
  from public.profiles
  where id = (select auth.uid());

  insert into public.chat_messages (
    conversation_id,
    sender_id,
    sender_name,
    body
  )
  values (
    p_conversation_id,
    (select auth.uid()),
    sender_display_name,
    trim(p_body)
  )
  returning id into created_message_id;

  update public.conversation_members
  set last_read_at = now()
  where conversation_id = p_conversation_id
    and user_id = (select auth.uid());

  return created_message_id;
end;
$$;

create or replace function public.mark_conversation_read(
  p_conversation_id uuid
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

  update public.conversation_members
  set last_read_at = now()
  where conversation_id = p_conversation_id
    and user_id = (select auth.uid());

  if not found then
    raise exception 'Only confirmed group members can read this conversation';
  end if;
end;
$$;

revoke all on function public.my_trip_conversations() from public;
grant execute on function public.my_trip_conversations() to authenticated;

revoke all on function public.send_chat_message(uuid, text) from public;
grant execute on function public.send_chat_message(uuid, text) to authenticated;

revoke all on function public.mark_conversation_read(uuid) from public;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_messages'
  ) then
    execute 'alter publication supabase_realtime add table public.chat_messages';
  end if;
end;
$$;
