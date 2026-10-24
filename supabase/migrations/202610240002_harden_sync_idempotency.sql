-- Harden replay semantics and lock acquisition order for concurrent local sync batches.
-- Existing receipts remain intact; this migration replaces only the RPC implementation.
begin;

create or replace function public.apply_qr_sync_batch(p_mutations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_mutation jsonb;
  v_key text;
  v_lock_key text;
  v_lock_record uuid;
  v_record_id uuid;
  v_type text;
  v_base_revision bigint;
  v_record jsonb;
  v_fingerprint text;
  v_existing_operation public.qr_sync_operations%rowtype;
  v_existing_record public.qr_records%rowtype;
  v_tombstone public.qr_record_tombstones%rowtype;
  v_revision bigint;
  v_status text;
  v_results jsonb := '[]'::jsonb;
begin
  if v_owner is null then
    raise exception 'authenticated session required' using errcode = '42501';
  end if;
  if p_mutations is null or jsonb_typeof(p_mutations) <> 'array' then
    raise exception 'mutations must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_mutations) > 100 then
    raise exception 'batch limit is 100 mutations' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_mutations) as item(value)
    where jsonb_typeof(value) <> 'object'
       or value->>'idempotency_key' is null
       or char_length(value->>'idempotency_key') not between 1 and 200
       or value->>'record_id' is null
  ) then
    raise exception 'each mutation needs an object, record id, and valid idempotency key' using errcode = '22023';
  end if;
  if exists (
    select value->>'idempotency_key'
    from jsonb_array_elements(p_mutations) as item(value)
    group by value->>'idempotency_key'
    having count(*) > 1
  ) then
    raise exception 'a batch cannot repeat an idempotency key' using errcode = '22023';
  end if;

  -- Acquire all idempotency locks first, then all record locks in stable order.
  -- This avoids deadlocks when two devices submit overlapping multi-record batches.
  for v_lock_key in
    select value->>'idempotency_key'
    from jsonb_array_elements(p_mutations) as item(value)
    order by value->>'idempotency_key'
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_owner::text || ':' || v_lock_key, 0)
    );
  end loop;
  for v_lock_record in
    select distinct (value->>'record_id')::uuid
    from jsonb_array_elements(p_mutations) as item(value)
    order by 1
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_owner::text || ':record:' || v_lock_record::text, 0)
    );
  end loop;

  -- Preserve client queue order so consecutive revisions for one record apply sequentially.
  for v_mutation in select value from jsonb_array_elements(p_mutations) as item(value)
  loop
    v_key := v_mutation->>'idempotency_key';
    v_record_id := (v_mutation->>'record_id')::uuid;
    v_type := v_mutation->>'type';
    v_base_revision := nullif(v_mutation->>'base_revision', '')::bigint;
    v_record := v_mutation->'record';

    if v_type is null or v_type not in ('upsert', 'delete') then
      raise exception 'unsupported mutation type' using errcode = '22023';
    end if;
    if v_base_revision < 0 then
      raise exception 'base revision cannot be negative' using errcode = '22023';
    end if;
    if v_type = 'upsert' and (
      jsonb_typeof(v_record) <> 'object'
      or (v_record->>'id')::uuid <> v_record_id
      or v_record->>'operation_type' is null
      or v_record->>'operation_type' not in ('create', 'read')
      or nullif(trim(v_record->>'symbology'), '') is null
      or nullif(trim(v_record->>'content_type'), '') is null
      or nullif(trim(v_record->>'content'), '') is null
    ) then
      raise exception 'invalid upsert record payload' using errcode = '22023';
    end if;
    if v_type = 'delete' and v_record is not null and v_record <> 'null'::jsonb then
      raise exception 'delete mutation cannot contain a record payload' using errcode = '22023';
    end if;

    v_fingerprint := md5(v_mutation::text);
    select * into v_existing_operation
      from public.qr_sync_operations
      where owner_id = v_owner and idempotency_key = v_key
      for update;

    if found then
      if v_existing_operation.request_fingerprint <> v_fingerprint then
        raise exception 'idempotency key reused with different request' using errcode = '22023';
      end if;
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'idempotency_key', v_key,
        'record_id', v_record_id,
        'status', case
          when v_existing_operation.result_status = 'conflict' then 'conflict'
          else 'already_applied'
        end,
        'original_status', v_existing_operation.result_status,
        'revision', v_existing_operation.result_revision
      ));
      continue;
    end if;

    select * into v_tombstone
      from public.qr_record_tombstones
      where owner_id = v_owner and record_id = v_record_id
      for update;

    if v_type = 'upsert' then
      if found then
        v_status := 'conflict';
        v_revision := v_tombstone.revision;
      else
        select * into v_existing_record
          from public.qr_records
          where id = v_record_id
          for update;

        if found and v_existing_record.author_id <> v_owner then
          v_status := 'conflict';
          v_revision := null;
        elsif found then
          if v_base_revision is null or v_base_revision <> v_existing_record.revision then
            v_status := 'conflict';
            v_revision := v_existing_record.revision;
          else
            update public.qr_records set
              operation_type = v_record->>'operation_type',
              symbology = v_record->>'symbology',
              content_type = v_record->>'content_type',
              content = v_record->>'content',
              name = coalesce(v_record->>'name', ''),
              description = coalesce(v_record->>'description', '')
            where id = v_record_id and author_id = v_owner;
            select revision into v_revision
              from public.qr_records where id = v_record_id and author_id = v_owner;
            v_status := 'applied';
          end if;
        elsif v_base_revision is not null then
          v_status := 'conflict';
          v_revision := null;
        else
          insert into public.qr_records (
            id, author_id, operation_type, symbology, content_type, content,
            name, description, created_at
          ) values (
            v_record_id, v_owner, v_record->>'operation_type',
            v_record->>'symbology', v_record->>'content_type',
            v_record->>'content', coalesce(v_record->>'name', ''),
            coalesce(v_record->>'description', ''),
            coalesce((v_record->>'created_at')::timestamptz, now())
          );
          select revision into v_revision
            from public.qr_records where id = v_record_id and author_id = v_owner;
          v_status := 'applied';
        end if;
      end if;
    else
      select * into v_existing_record
        from public.qr_records
        where id = v_record_id
        for update;
      if found and v_existing_record.author_id <> v_owner then
        v_status := 'conflict';
        v_revision := null;
      elsif found then
        if v_base_revision is null or v_base_revision <> v_existing_record.revision then
          v_status := 'conflict';
          v_revision := v_existing_record.revision;
        else
          v_revision := v_existing_record.revision + 1;
          delete from public.qr_records where author_id = v_owner and id = v_record_id;
          insert into public.qr_record_tombstones(owner_id, record_id, revision, idempotency_key)
          values (v_owner, v_record_id, v_revision, v_key)
          on conflict (owner_id, record_id) do update
            set revision = excluded.revision,
                idempotency_key = excluded.idempotency_key,
                deleted_at = clock_timestamp();
          v_status := 'applied';
        end if;
      elsif v_tombstone.record_id is not null then
        v_status := 'already_applied';
        v_revision := v_tombstone.revision;
      else
        v_revision := coalesce(v_base_revision, 0) + 1;
        insert into public.qr_record_tombstones(owner_id, record_id, revision, idempotency_key)
        values (v_owner, v_record_id, v_revision, v_key);
        v_status := 'applied';
      end if;
    end if;

    insert into public.qr_sync_operations(
      owner_id, idempotency_key, record_id, mutation_type,
      request_fingerprint, result_status, result_revision
    ) values (
      v_owner, v_key, v_record_id, v_type, v_fingerprint, v_status, v_revision
    );

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'idempotency_key', v_key,
      'record_id', v_record_id,
      'status', v_status,
      'revision', v_revision
    ));
  end loop;

  return v_results;
end;
$$;

revoke all on function public.apply_qr_sync_batch(jsonb) from public, anon;
grant execute on function public.apply_qr_sync_batch(jsonb) to authenticated;

commit;
