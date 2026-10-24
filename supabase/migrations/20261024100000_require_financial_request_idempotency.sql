begin;

-- The current BDX-only RPC replaced an earlier guarded implementation and
-- accidentally stopped rejecting NULL request IDs. Restore the invariant at
-- the database boundary so retries cannot create unkeyed duplicate requests.
create or replace function public.create_financial_transaction(
  p_type text,
  p_amount numeric,
  p_method text,
  p_note text,
  p_request_id uuid,
  p_currency text
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_tx public.transaction;
  v_currency text := upper(trim(coalesce(p_currency,'')));
  v_method text := upper(trim(coalesce(p_method,'')));
  v_address text := btrim(coalesce(p_note,''));
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if p_type not in ('deposit','withdraw') then raise exception 'Invalid transaction type'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if p_request_id is null then raise exception 'Request ID is required for idempotency'; end if;
  if v_currency <> 'BDX' then raise exception 'Only BDX accounting is supported'; end if;
  if v_method <> 'BELDEX' then raise exception 'Only Beldex transactions are supported'; end if;
  if p_type='deposit' and p_amount < 4000 then raise exception 'Minimum deposit is 4000 BDX'; end if;
  if p_type='withdraw' and p_amount < 76 then raise exception 'Minimum withdrawal is 76 BDX'; end if;
  if p_type='withdraw' and (
    v_address !~ '^[1-9A-HJ-NP-Za-km-z]+$' or length(v_address) < 90 or length(v_address) > 110
  ) then raise exception 'Invalid Beldex destination address'; end if;
  perform public.assert_user_can_transact(v_uid);

  select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
  if found then
    if v_tx.type <> p_type or v_tx.amount <> p_amount
      or coalesce(v_tx.currency,'USD') <> v_currency
      or upper(coalesce(v_tx.method,'')) <> v_method
      or coalesce(v_tx.note,'') <> (case when p_type='withdraw' then v_address else '' end) then
      raise exception 'Request ID was already used for a different transaction';
    end if;
    return v_tx;
  end if;

  if p_type='withdraw' then
    update public.user_profile set bdx_balance=bdx_balance-p_amount,updated_at=now()
    where user_id=v_uid and bdx_balance>=p_amount;
    if not found then raise exception 'Insufficient BDX balance'; end if;
  end if;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note,request_id)
  values(v_uid,p_type,p_amount,'BDX','pending','awaiting','Beldex',
    case when p_type='withdraw' then v_address else null end,p_request_id)
  returning * into v_tx;
  return v_tx;
exception when unique_violation then
  select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
  if found and v_tx.type=p_type and v_tx.amount=p_amount
    and coalesce(v_tx.currency,'USD')=v_currency
    and upper(coalesce(v_tx.method,''))=v_method
    and coalesce(v_tx.note,'')=(case when p_type='withdraw' then v_address else '' end) then
    return v_tx;
  end if;
  raise;
end;
$function$;

revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid,text) from public, anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid,text) to authenticated;

commit;
