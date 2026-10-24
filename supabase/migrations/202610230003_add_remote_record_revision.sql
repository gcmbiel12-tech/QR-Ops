-- Sync-readiness metadata only. No sync is enabled by this migration.
-- Preserve all existing records and their original created_at timestamps.
begin;

alter table public.qr_records
  add column if not exists updated_at timestamptz not null default now();

alter table public.qr_records
  add column if not exists revision bigint not null default 1
  check (revision > 0);

create index if not exists qr_records_author_updated_at_idx
  on public.qr_records (author_id, updated_at desc, id);

create or replace function public.set_qr_record_update_metadata()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.statement_timestamp();
  new.revision := old.revision + 1;
  return new;
end;
$$;

revoke all on function public.set_qr_record_update_metadata() from public, anon, authenticated;

drop trigger if exists qr_records_set_update_metadata on public.qr_records;
create trigger qr_records_set_update_metadata
before update on public.qr_records
for each row execute function public.set_qr_record_update_metadata();

commit;
