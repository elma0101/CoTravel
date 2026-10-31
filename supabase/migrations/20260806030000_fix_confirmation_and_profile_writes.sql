-- The local variable shared a name with a conversation_members column, so every
-- traveler confirmation failed with an ambiguous column reference.
create or replace function public.open_chat_after_trip_confirmation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_conversation_id uuid;
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
  returning id into target_conversation_id;

  insert into public.conversation_members (conversation_id, user_id)
  values
    (target_conversation_id, trip_host_id),
    (target_conversation_id, new.traveler_id)
  on conflict (conversation_id, user_id) do nothing;

  insert into public.chat_messages (
    conversation_id,
    sender_id,
    sender_name,
    body,
    message_type
  )
  values (
    target_conversation_id,
    null,
    null,
    traveler_name || ' confirmed their place. The trip chat is now open.',
    'system'
  );

  return new;
end;
$$;

-- Direct writes let a user set linkedin_verified_at on their own row. Profiles
-- are only written through complete_profile and sync_my_linkedin_verification.
revoke insert, update, delete on public.profiles from anon, authenticated;

-- Any account that granted itself verification through the old path loses it
-- unless a real LinkedIn identity backs the claim.
update public.profiles as profile
set linkedin_verified_at = null
where profile.linkedin_verified_at is not null
  and not exists (
    select 1
    from auth.identities as identity
    where identity.user_id = profile.id
      and identity.provider = 'linkedin_oidc'
  );

-- The output column conversation_id conflicted with the ON CONFLICT target, so
-- every chat message failed to send.
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
#variable_conflict use_column
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

-- Earlier migrations revoked only from PUBLIC. Supabase's default privileges can
-- also grant API roles directly, so the intended boundary is stated explicitly.
do $$
declare
  target record;
begin
  for target in
    select class.relname
    from pg_catalog.pg_class as class
    join pg_catalog.pg_namespace as namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public' and class.relkind in ('r', 'v')
  loop
    execute format('revoke all on public.%I from anon', target.relname);
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on public.%I from authenticated',
      target.relname
    );
  end loop;

  for target in
    select procedure.oid::regprocedure as signature
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
  loop
    execute format('revoke all on function %s from anon', target.signature);
  end loop;
end;
$$;

revoke all on public.user_blocks, public.safety_reports, public.analytics_events
from authenticated;

revoke all on function public.seed_controlled_beta_trips(uuid, text)
from authenticated;
revoke all on function public.capture_poc_validation_snapshot(
  boolean,
  boolean,
  integer,
  text
) from authenticated;

-- Replaced by send_chat_message_v2, which also prevents duplicate retries.
revoke all on function public.send_chat_message(uuid, text) from authenticated;
