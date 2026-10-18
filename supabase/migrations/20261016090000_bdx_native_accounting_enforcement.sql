begin;

-- The published percentages are daily simple-interest rates. New investments
-- snapshot these rates; existing investment rows keep their recorded rate.
-- Accrual is principal * daily_rate * elapsed whole days, credited daily.
update public.investment_plan_catalog
set daily_rate = case id
  when 'gns' then 0.019
  when 'build' then 0.0251
  when 'follow' then 0.0392
  when 'apex' then 0.0856
  when 'edifex' then 0.1343
  when 'dixon' then 0.1543
  when 'falcon' then 0.2378
  else daily_rate
end,
updated_at = now()
where id in ('gns','build','follow','apex','edifex','dixon','falcon');

-- Financial requests must use the denomination implied by the payment method.
-- Beldex requests are BDX only; BTC/ETH requests remain USD-denominated.
-- The database validates the minimum, destination, blocked status, balance
-- reservation, and idempotency even when the browser is bypassed.
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
  if v_currency not in ('BDX','USD') then raise exception 'Unsupported currency'; end if;
  if v_method not in ('BELDEX','BITCOIN','ETHEREUM') then raise exception 'Invalid payment method'; end if;

  if v_method='BELDEX' then
    if v_currency <> 'BDX' then raise exception 'Beldex transactions must be denominated in BDX'; end if;
    if p_amount < 4000 then raise exception 'Minimum Beldex amount is 4000 BDX'; end if;
  else
    if v_currency <> 'USD' then raise exception 'Bitcoin and Ethereum requests must use USD denomination'; end if;
    if p_amount < 300 then raise exception 'Minimum amount is 300 USD'; end if;
  end if;

  if p_type='withdraw' then
    if v_address='' then raise exception 'Please enter a destination address'; end if;
    if v_method='ETHEREUM' and v_address !~ '^0x[0-9A-Fa-f]{40}$' then
      raise exception 'Invalid Ethereum destination address';
    end if;
    if v_method='BITCOIN'
      and v_address !~* '^bc1[ac-hj-np-z02-9]{11,71}$'
      and v_address !~ '^[13][1-9A-HJ-NP-Za-km-z]{25,34}$'
    then
      raise exception 'Invalid Bitcoin destination address';
    end if;
    if v_method='BELDEX' and (
      v_address !~ '^[1-9A-HJ-NP-Za-km-z]+$'
      or length(v_address) < 90
      or length(v_address) > 110
    ) then
      raise exception 'Invalid Beldex destination address';
    end if;
  end if;

  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx
      from public.transaction
     where user_id=v_uid and request_id=p_request_id
     limit 1;
    if found then
      if v_tx.type <> p_type
        or v_tx.amount <> p_amount
        or coalesce(v_tx.currency,'USD') <> v_currency
        or upper(coalesce(v_tx.method,'')) <> v_method
        or coalesce(v_tx.note,'') <> v_address
      then
        raise exception 'Request ID was already used for a different transaction';
      end if;
      return v_tx;
    end if;
  end if;

  if p_type='withdraw' then
    if v_currency='BDX' then
      update public.user_profile
         set bdx_balance=bdx_balance-p_amount, updated_at=now()
       where user_id=v_uid and bdx_balance>=p_amount;
    else
      update public.user_profile
         set available_balance=available_balance-p_amount, updated_at=now()
       where user_id=v_uid and available_balance>=p_amount;
    end if;
    if not found then raise exception 'Insufficient % balance',v_currency; end if;
  end if;

  insert into public.transaction(
    user_id,type,amount,currency,status,approval_status,method,note,request_id
  )
  values(
    v_uid,p_type,p_amount,v_currency,'pending','awaiting',p_method,
    case when p_type='withdraw' then v_address else null end,p_request_id
  )
  returning * into v_tx;
  return v_tx;
exception when unique_violation then
  if p_request_id is not null then
    select * into v_tx
      from public.transaction
     where user_id=v_uid and request_id=p_request_id
     limit 1;
    if found
      and v_tx.type=p_type
      and v_tx.amount=p_amount
      and coalesce(v_tx.currency,'USD')=v_currency
      and upper(coalesce(v_tx.method,''))=v_method
      and coalesce(v_tx.note,'')=v_address
    then
      return v_tx;
    end if;
  end if;
  raise;
end;
$function$;

revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid,text) from public,anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid,text) to authenticated;

-- Remove legacy overloads that could create requests without specifying currency.
drop function if exists public.create_financial_transaction(text,numeric,text,text,uuid);
drop function if exists public.create_financial_transaction(text,numeric,text,text);

-- Retire currency swaps without breaking an already-deployed Edge Function.
-- The service-role endpoint may remain deployed until explicitly removed, so keep
-- its UUID-signature RPC as a fail-closed compatibility stub. It never writes
-- balances or transactions and returns a clear error. Direct client calls remain
-- revoked. The obsolete text-signature overload is removed.
create or replace function public.swap_assets(
  p_user_id uuid,
  p_from text,
  p_to text,
  p_amount numeric,
  p_rate numeric
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
begin
  raise exception 'Currency swaps are retired; use the BDX-native wallet flow';
end;
$function$;

revoke all on function public.swap_assets(uuid,text,text,numeric,numeric) from public, anon, authenticated;
grant execute on function public.swap_assets(uuid,text,text,numeric,numeric) to service_role;
drop function if exists public.swap_assets(text,text,numeric,numeric);

commit;
