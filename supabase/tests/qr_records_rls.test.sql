-- Run only against a disposable Supabase development database after applying
-- the migrations. pgTAP is required (supabase test db).
begin;
select plan(25);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('a1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rls-a@example.invalid', '', now(), now(), now()),
  ('b2000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rls-b@example.invalid', '', now(), now(), now())
on conflict (id) do nothing;

set local role service_role;
insert into public.qr_records (id, author_id, operation_type, symbology, content_type, content, created_at)
values
  ('a1000000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-000000000001', 'create', 'qr', 'text', 'private-A', now()),
  ('b2000000-0000-4000-8000-000000000022', 'b2000000-0000-4000-8000-000000000002', 'create', 'qr', 'text', 'private-B', now())
on conflict (id) do update set content = excluded.content;
reset role;

select ok((select relrowsecurity from pg_class where oid = 'public.qr_records'::regclass), 'RLS is enabled');
select ok((select relforcerowsecurity from pg_class where oid = 'public.qr_records'::regclass), 'RLS is forced for table owners');
select has_column('public', 'qr_records', 'updated_at', 'updated_at exists for future synchronization');
select has_column('public', 'qr_records', 'revision', 'revision exists for optimistic concurrency');
select ok((select count(*) = 1 from pg_trigger where tgrelid = 'public.qr_records'::regclass and tgname = 'qr_records_set_update_metadata' and not tgisinternal), 'revision trigger exists');
select is((select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'qr_records'), 4, 'only the four owner-scoped policies exist');
select ok(
  not has_table_privilege('anon', 'public.qr_records', 'SELECT')
  and not has_table_privilege('anon', 'public.qr_records', 'INSERT')
  and not has_table_privilege('anon', 'public.qr_records', 'UPDATE')
  and not has_table_privilege('anon', 'public.qr_records', 'DELETE'),
  'anon has no CRUD privileges'
);
select ok(
  has_table_privilege('authenticated', 'public.qr_records', 'SELECT')
  and has_table_privilege('authenticated', 'public.qr_records', 'INSERT')
  and has_table_privilege('authenticated', 'public.qr_records', 'UPDATE')
  and has_table_privilege('authenticated', 'public.qr_records', 'DELETE'),
  'authenticated has the intended CRUD privileges'
);

select ok(
  not has_table_privilege('anon', 'public.qr_records', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.qr_records', 'TRUNCATE')
  and not has_function_privilege('anon', 'public.set_qr_record_update_metadata()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.set_qr_record_update_metadata()', 'EXECUTE')
  and not exists (select 1 from aclexplode(coalesce((select relacl from pg_class where oid = 'public.qr_records'::regclass), acldefault('r', (select relowner from pg_class where oid = 'public.qr_records'::regclass)))) a where a.grantee = 0 and a.privilege_type in ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')),
  'no excess truncate, trigger-function execution, or PUBLIC table grants'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);
select is((select count(*)::int from public.qr_records), 1, 'user A sees only their own record');
select is((select count(*)::int from public.qr_records where id = 'b2000000-0000-4000-8000-000000000022'), 0, 'user A cannot select user B record');
with changed as (update public.qr_records set content = 'stolen' where id = 'b2000000-0000-4000-8000-000000000022' returning id) select is((select count(*)::int from changed), 0, 'user A cannot update user B record');
with removed as (delete from public.qr_records where id = 'b2000000-0000-4000-8000-000000000022' returning id) select is((select count(*)::int from removed), 0, 'user A cannot delete user B record');
select lives_ok($$insert into public.qr_records (id, author_id, operation_type, symbology, content_type, content, created_at) values ('a1000000-0000-4000-8000-000000000033', 'a1000000-0000-4000-8000-000000000001', 'create', 'qr', 'text', 'owned insert', '2020-01-02 03:04:05+00')$$, 'user A can insert a record owned by A');
select lives_ok($$update public.qr_records set content = 'owned update' where id = 'a1000000-0000-4000-8000-000000000033'$$, 'user A can update own record');
select is((select revision::int from public.qr_records where id = 'a1000000-0000-4000-8000-000000000033'), 2, 'revision increments on update');
select ok((select updated_at > created_at from public.qr_records where id = 'a1000000-0000-4000-8000-000000000033'), 'updated_at advances when a record is updated');
select is((select created_at from public.qr_records where id = 'a1000000-0000-4000-8000-000000000033'), '2020-01-02 03:04:05+00'::timestamptz, 'created_at is preserved by update trigger');
select throws_ok($$insert into public.qr_records (id, author_id, operation_type, symbology, content_type, content) values ('a1000000-0000-4000-8000-000000000044', 'b2000000-0000-4000-8000-000000000002', 'create', 'qr', 'text', 'spoofed owner')$$, '42501', null, 'user A cannot spoof author_id');
select throws_ok($$update public.qr_records set author_id = 'b2000000-0000-4000-8000-000000000002' where id = 'a1000000-0000-4000-8000-000000000011'$$, '42501', null, 'user A cannot transfer ownership by updating author_id');

select set_config('request.jwt.claim.sub', 'b2000000-0000-4000-8000-000000000002', true);
select is((select count(*)::int from public.qr_records), 1, 'switching claim to user B exposes only B record');

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select count(*) from public.qr_records$$, '42501', null, 'anonymous role cannot select records');
select throws_ok($$insert into public.qr_records (id, author_id, operation_type, symbology, content_type, content) values ('c3000000-0000-4000-8000-000000000055', 'a1000000-0000-4000-8000-000000000001', 'create', 'qr', 'text', 'anonymous insert')$$, '42501', null, 'anonymous role cannot insert records');
select throws_ok($$update public.qr_records set content = 'anonymous edit' where id = 'a1000000-0000-4000-8000-000000000011'$$, '42501', null, 'anonymous role cannot update records');
select throws_ok($$delete from public.qr_records where id = 'a1000000-0000-4000-8000-000000000011'$$, '42501', null, 'anonymous role cannot delete records');

select * from finish();
rollback;
