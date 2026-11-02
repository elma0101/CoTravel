-- Crash reports stay service-only, and push tokens keep their language.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

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

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000c9', 'member@example.test');

select pg_temp.act_as('00000000-0000-4000-8000-0000000000c9');

select lives_ok(
  $$ select public.report_client_error('StateError', 'frame', '0.9.0', 'android') $$,
  'a signed-in member can send a crash report'
);

select throws_ok(
  $$ select public.report_client_error('StateError', repeat('x', 4001), '0.9.0', 'android') $$,
  '23514',
  null,
  'an oversized report is refused'
);

select throws_ok(
  $$ select * from public.client_errors $$,
  '42501',
  null,
  'members cannot read crash reports'
);

select throws_ok(
  $$ insert into public.client_errors (kind, stack, app_version, platform)
     values ('a', 'b', 'c', 'd') $$,
  '42501',
  null,
  'members cannot write crash reports directly'
);

select lives_ok(
  $$ select public.register_push_token('phone', 'fr') $$,
  'a device can register in French'
);

select throws_ok(
  $$ select public.register_push_token('phone', 'de') $$,
  '23514',
  null,
  'an unsupported language is refused'
);

reset role;

select is(
  (select language from public.push_tokens where token = 'phone'),
  'fr',
  'the language is stored'
);

select is(
  (select count(*)::int from public.client_errors),
  1,
  'the accepted report was stored'
);

select * from finish();
rollback;
