-- QR Ops: historico global compartilhado.
-- Execute via Supabase CLI migrations ou SQL Editor apos revisar o ambiente.
create table if not exists public.qr_records (
  id uuid primary key,
  author_id uuid not null references auth.users(id) on delete restrict,
  operation_type text not null check (operation_type in ('create', 'read')),
  symbology text not null check (char_length(symbology) between 1 and 40),
  content_type text not null check (char_length(content_type) between 1 and 80),
  content text not null check (char_length(trim(content)) between 1 and 10000),
  created_at timestamptz not null default now()
);

create index if not exists qr_records_created_at_idx
  on public.qr_records (created_at desc, id desc);
create index if not exists qr_records_author_created_at_idx
  on public.qr_records (author_id, created_at desc);

alter table public.qr_records enable row level security;

-- Historico global: qualquer usuario autenticado pode consultar.
drop policy if exists "authenticated users can read shared history" on public.qr_records;
create policy "authenticated users can read shared history"
  on public.qr_records for select
  to authenticated
  using (true);

-- A autoria e validada pelo servidor, nunca confiada ao cliente.
drop policy if exists "users can insert own records" on public.qr_records;
create policy "users can insert own records"
  on public.qr_records for insert
  to authenticated
  with check (author_id = (select auth.uid()));

-- Sem policy UPDATE intencionalmente: registros sao imutaveis.
-- Cada usuario pode excluir apenas registros que criou.
drop policy if exists "users can delete own records" on public.qr_records;
create policy "users can delete own records"
  on public.qr_records for delete
  to authenticated
  using (author_id = (select auth.uid()));

grant select, insert, delete on public.qr_records to authenticated;
revoke all on public.qr_records from anon;
