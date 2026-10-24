begin;

-- Keep legacy five-argument callers compatible, but route every request through
-- the BDX-only guarded implementation. This prevents the old USD/multi-asset
-- path from bypassing request-id, balance, and denomination safeguards.
create or replace function public.create_financial_transaction(
  p_type text,
  p_amount numeric,
  p_method text default null,
  p_note text default null,
  p_request_id uuid default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
begin
  return public.create_financial_transaction(
    p_type,
    p_amount,
    p_method,
    p_note,
    p_request_id,
    'BDX'
  );
end;
$function$;

revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid) from public, anon, authenticated, service_role;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid) to authenticated;

commit;
