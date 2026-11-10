begin;

-- A exclusão da conta deve remover os registros de QR associados na mesma
-- transação do Auth Admin API, evitando contas órfãs bloqueadas por FK.
alter table public.qr_records
  drop constraint if exists qr_records_author_id_fkey;

alter table public.qr_records
  add constraint qr_records_author_id_fkey
  foreign key (author_id)
  references auth.users(id)
  on delete cascade;

commit;
