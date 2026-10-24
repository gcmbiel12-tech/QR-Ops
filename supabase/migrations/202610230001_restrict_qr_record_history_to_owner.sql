-- SECURITY PREPARATION ONLY: review and apply in a controlled Supabase environment.
-- Never execute automatically against production.
-- Owner-only RLS for every row operation exposed by the client.

begin;

alter table public.qr_records enable row level security;
alter table public.qr_records force row level security;

-- Remove every existing policy, including unknown dashboard-created policies.
-- PostgreSQL permissive policies are OR-combined; leaving one global policy would
-- silently defeat owner isolation.
do $$
declare
  existing_policy record;
begin
  for existing_policy in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'qr_records'
  loop
    execute format('drop policy %I on public.qr_records', existing_policy.policyname);
  end loop;
end
$$;

create policy "users can read own records"
  on public.qr_records for select
  to authenticated
  using (author_id = (select auth.uid()));

create policy "users can insert own records"
  on public.qr_records for insert
  to authenticated
  with check (author_id = (select auth.uid()));

create policy "users can update own records"
  on public.qr_records for update
  to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

create policy "users can delete own records"
  on public.qr_records for delete
  to authenticated
  using (author_id = (select auth.uid()));

-- Remove inherited/default grants, then allow only the intended client role.
revoke all on table public.qr_records from public, anon, authenticated;
grant select, insert, update, delete on table public.qr_records to authenticated;

commit;
