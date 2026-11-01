-- Push token ownership. Everything rolls back.
begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'first@example.test'),
  ('00000000-0000-4000-8000-0000000000a2', 'second@example.test');

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

select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');

select lives_ok(
  $$ select public.register_push_token('shared-phone') $$,
  'a signed-in user can register a device'
);

select throws_ok(
  $$ select * from public.push_tokens $$,
  '42501',
  null,
  'users cannot read device tokens'
);

select throws_ok(
  $$ delete from public.push_tokens $$,
  '42501',
  null,
  'users cannot delete device tokens directly'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');

select lives_ok(
  $$ select public.register_push_token('shared-phone') $$,
  'the next user on a device can register it'
);

reset role;

select is(
  (select user_id from public.push_tokens where token = 'shared-phone'),
  '00000000-0000-4000-8000-0000000000a2'::uuid,
  'the device belongs only to the latest user'
);

select is(
  (select count(*)::integer from public.push_tokens),
  1,
  'registering again does not duplicate the device'
);

select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$ select public.register_push_token('anonymous-device') $$,
  '42501',
  null,
  'anonymous callers cannot register a device'
);

reset role;

select * from finish();

rollback;
