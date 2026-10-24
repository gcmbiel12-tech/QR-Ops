begin;
select plan(17);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
 ('a1000000-0000-4000-8000-000000000001','authenticated','authenticated','sync-a@example.invalid','',now(),now(),now()),
 ('b2000000-0000-4000-8000-000000000002','authenticated','authenticated','sync-b@example.invalid','',now(),now(),now())
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);

select ok(
  (public.apply_qr_sync_batch('[{"idempotency_key":"sync-create-1","record_id":"a1000000-0000-4000-8000-000000000101","type":"upsert","base_revision":null,"record":{"id":"a1000000-0000-4000-8000-000000000101","operation_type":"create","symbology":"qr","content_type":"text","content":"original","name":"","description":"","created_at":"2026-10-24T00:00:00Z"}}]'::jsonb)->0->>'status') = 'applied',
  'first upsert is applied'
);
select is((select count(*)::int from public.qr_records where id='a1000000-0000-4000-8000-000000000101'),1,'first upsert creates one active record');
select is((public.apply_qr_sync_batch('[{"idempotency_key":"sync-create-1","record_id":"a1000000-0000-4000-8000-000000000101","type":"upsert","base_revision":null,"record":{"id":"a1000000-0000-4000-8000-000000000101","operation_type":"create","symbology":"qr","content_type":"text","content":"original","name":"","description":"","created_at":"2026-10-24T00:00:00Z"}}]'::jsonb)->0->>'status'),'already_applied','retry with same key is acknowledged idempotently');
select is((select count(*)::int from public.qr_sync_operations where owner_id=auth.uid() and idempotency_key='sync-create-1'),1,'duplicate retry creates one operation receipt');
select throws_ok($$select public.apply_qr_sync_batch('[{"idempotency_key":"sync-create-1","record_id":"a1000000-0000-4000-8000-000000000101","type":"upsert","base_revision":null,"record":{"id":"a1000000-0000-4000-8000-000000000101","operation_type":"create","symbology":"qr","content_type":"text","content":"tampered","name":"","description":""}}]'::jsonb)$$,'22023',null,'same key cannot be reused with a different payload');

select is((public.apply_qr_sync_batch('[{"idempotency_key":"sync-update-2","record_id":"a1000000-0000-4000-8000-000000000101","type":"upsert","base_revision":1,"record":{"id":"a1000000-0000-4000-8000-000000000101","operation_type":"create","symbology":"qr","content_type":"text","content":"updated","name":"","description":""}}]'::jsonb)->0->>'status'),'applied','update with matching revision succeeds');
select is((select revision::int from public.qr_records where id='a1000000-0000-4000-8000-000000000101'),2,'update increments revision');
select is((public.apply_qr_sync_batch('[{"idempotency_key":"sync-stale-update","record_id":"a1000000-0000-4000-8000-000000000101","type":"upsert","base_revision":1,"record":{"id":"a1000000-0000-4000-8000-000000000101","operation_type":"create","symbology":"qr","content_type":"text","content":"stale","name":"","description":""}}]'::jsonb)->0->>'status'),'conflict','stale update is rejected');
select is((public.apply_qr_sync_batch('[{"idempotency_key":"sync-stale-update","record_id":"a1000000-0000-4000-8000-000000000101","type":"upsert","base_revision":1,"record":{"id":"a1000000-0000-4000-8000-000000000101","operation_type":"create","symbology":"qr","content_type":"text","content":"stale","name":"","description":""}}]'::jsonb)->0->>'status'),'conflict','retrying a recorded conflict remains a conflict');
select is((select content from public.qr_records where id='a1000000-0000-4000-8000-000000000101'),'updated','stale update does not overwrite newer content');

select is((public.apply_qr_sync_batch('[{"idempotency_key":"sync-stale-delete","record_id":"a1000000-0000-4000-8000-000000000101","type":"delete","base_revision":1}]'::jsonb)->0->>'status'),'conflict','stale delete is rejected');
select is((public.apply_qr_sync_batch('[{"idempotency_key":"sync-delete-3","record_id":"a1000000-0000-4000-8000-000000000101","type":"delete","base_revision":2}]'::jsonb)->0->>'status'),'applied','delete at matching revision succeeds');
select is((select count(*)::int from public.qr_records where id='a1000000-0000-4000-8000-000000000101'),0,'deleted record is no longer active');
select is((select revision::int from public.qr_record_tombstones where owner_id=auth.uid() and record_id='a1000000-0000-4000-8000-000000000101'),3,'delete persists tombstone with next revision');
select is((public.apply_qr_sync_batch('[{"idempotency_key":"sync-old-upsert","record_id":"a1000000-0000-4000-8000-000000000101","type":"upsert","base_revision":null,"record":{"id":"a1000000-0000-4000-8000-000000000101","operation_type":"create","symbology":"qr","content_type":"text","content":"resurrection","name":"","description":""}}]'::jsonb)->0->>'status'),'conflict','old upsert cannot resurrect tombstoned record');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
select is((select count(*)::int from public.qr_sync_operations where owner_id='a1000000-0000-4000-8000-000000000001'),0,'user B cannot read user A operation receipts');
select is((select count(*)::int from public.qr_record_tombstones where owner_id='a1000000-0000-4000-8000-000000000001'),0,'user B cannot read user A tombstones');

reset role;
select * from finish();
rollback;
