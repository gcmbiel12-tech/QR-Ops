-- Add optional library metadata without dropping or rewriting existing records.
begin;
alter table public.qr_records add column if not exists name text not null default '';
alter table public.qr_records add column if not exists description text not null default '';
commit;