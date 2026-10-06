-- Milestone 19: validate withdrawal destinations server-side.
-- Frontend validation is UX only; this RPC remains the financial enforcement boundary.
-- Beldex validation here is syntax/length based. A real payout service should
-- additionally call the Beldex wallet/RPC validate_address method before broadcast.

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
declare
  v_tx public.transaction;
  v_uid uuid := auth.uid();
  v_address text := btrim(coalesce(p_note, ''));
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;

  if p_type not in ('deposit','withdraw') then
    raise exception 'Invalid transaction type';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if p_type = 'withdraw' then
    if p_amount < 300 then
      raise exception 'Minimum withdrawal is 300';
    end if;

    if p_method not in ('Bitcoin', 'Ethereum', 'Beldex') then
      raise exception 'Invalid withdrawal method';
    end if;

    if v_address = '' then
      raise exception 'Please enter a destination address';
    end if;

    if p_method = 'Ethereum' and v_address !~ '^0x[0-9A-Fa-f]{40}$' then
      raise exception 'Invalid Ethereum destination address';
    end if;

    if p_method = 'Bitcoin'
      and v_address !~* '^bc1[ac-hj-np-z02-9]{11,71}$'
      and v_address !~ '^[13][1-9A-HJ-NP-Za-km-z]{25,34}$'
    then
      raise exception 'Invalid Bitcoin destination address';
    end if;

    if p_method = 'Beldex'
      and (
        v_address !~ '^[1-9A-HJ-NP-Za-km-z]+$'
        or length(v_address) < 90
        or length(v_address) > 110
      )
    then
      raise exception 'Invalid Beldex destination address';
    end if;
  end if;

  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx
      from public.transaction
     where user_id = v_uid and request_id = p_request_id
     limit 1;
    if found then return v_tx; end if;
  end if;

  if p_type = 'withdraw' then
    update public.user_profile
      set available_balance = available_balance - p_amount, updated_at = now()
      where user_id = v_uid and available_balance >= p_amount;
    if not found then raise exception 'Insufficient balance'; end if;
  end if;

  insert into public.transaction(user_id,type,amount,status,approval_status,method,note,request_id)
  values (v_uid,p_type,p_amount,'pending','awaiting',p_method,v_address,p_request_id)
  returning * into v_tx;

  return v_tx;
exception
  when unique_violation then
    if p_request_id is not null then
      select * into v_tx
        from public.transaction
       where user_id = v_uid and request_id = p_request_id
       limit 1;
      if found then return v_tx; end if;
    end if;
    raise;
end;
$function$;

alter function public.create_financial_transaction(text,numeric,text,text,uuid)
  security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid) from public, anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid) to authenticated;
