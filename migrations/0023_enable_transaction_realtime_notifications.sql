begin;

-- Keep the transaction table in Supabase Realtime so authenticated
-- clients can receive deposit/withdrawal/status changes immediately.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'transaction'
  ) then
    alter publication supabase_realtime add table public.transaction;
  end if;
end
$$;

commit;
