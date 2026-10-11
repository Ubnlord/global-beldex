begin;

-- BDX-native investment accounting. Existing investments and transactions stay
-- USD-denominated by default; only new purchases explicitly use BDX.
alter table public.user_profile
  add column if not exists locked_bdx_balance numeric(38,18) not null default 0;

alter table public.user_investment
  add column if not exists currency text not null default 'USD'
    check (currency in ('USD','BDX'));

alter table public.transaction
  add column if not exists currency text not null default 'USD'
    check (currency in ('USD','BDX'));

-- New purchases are denominated and debited in BDX. The plan catalog's min/max
-- amounts already represent BDX amounts. Never convert these to USD here.
create or replace function public.buy_investment_plan(p_plan_id text,p_amount numeric)
returns public.user_investment
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_plan public.investment_plan_catalog;
  v_profile public.user_profile;
  v_inv public.user_investment;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  perform public.assert_user_can_transact(v_uid);
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;

  select * into v_plan
  from public.investment_plan_catalog
  where id = p_plan_id and active;
  if v_plan.id is null then raise exception 'Investment plan not found'; end if;
  if p_amount < v_plan.min_amount then raise exception 'Minimum investment is % BDX',v_plan.min_amount; end if;
  if v_plan.max_amount is not null and p_amount > v_plan.max_amount then
    raise exception 'Maximum investment is % BDX',v_plan.max_amount;
  end if;

  select * into v_profile from public.user_profile where user_id = v_uid for update;
  if v_profile.user_id is null then raise exception 'Profile not found'; end if;
  if v_profile.bdx_balance < p_amount then raise exception 'Insufficient BDX balance'; end if;

  update public.user_profile
  set bdx_balance = bdx_balance - p_amount,
      locked_bdx_balance = locked_bdx_balance + p_amount,
      updated_at = now()
  where user_id = v_uid;

  insert into public.user_investment(user_id,plan_id,principal,daily_rate,duration_days,currency)
  values(v_uid,v_plan.id,p_amount,v_plan.daily_rate,v_plan.duration_days,'BDX')
  returning * into v_inv;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
  values(v_uid,'plan',p_amount,'BDX','completed','approved',v_plan.name,'BDX-denominated investment purchase');
  return v_inv;
end;
$function$;

revoke all on function public.buy_investment_plan(text,numeric) from public, anon;
grant execute on function public.buy_investment_plan(text,numeric) to authenticated;

-- Accrue by each investment's recorded currency. Row locks plus last_accrual_at
-- make retries safe; maturity principal is returned in the same currency once.
create or replace function public.accrue_user_investments(p_user_id uuid default auth.uid())
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_inv public.user_investment;
  v_now timestamptz := now();
  v_elapsed_days integer;
  v_previous_days integer;
  v_days integer;
  v_profit numeric;
  v_principal_return numeric;
  v_total numeric := 0;
  v_done boolean;
  v_admin boolean := public.is_admin();
  v_scheduled boolean := auth.uid() is null;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if v_uid <> auth.uid() then
    if not v_scheduled and (not v_admin or not public.admin_has_permission('manage_users')) then
      raise exception 'Permission denied';
    end if;
  end if;
  perform public.assert_user_can_transact(v_uid);

  for v_inv in
    select * from public.user_investment
    where user_id = v_uid and status = 'active' and daily_accrual_enabled = true
    order by created_at
    for update
  loop
    v_elapsed_days := least(v_inv.duration_days,
      greatest(0, floor(extract(epoch from (v_now - v_inv.started_at))/86400)::integer));
    v_previous_days := least(v_inv.duration_days,
      greatest(0, floor(extract(epoch from (v_inv.last_accrual_at - v_inv.started_at))/86400)::integer));
    v_days := greatest(0, v_elapsed_days - v_previous_days);

    if v_days > 0 then
      v_profit := v_inv.principal * v_inv.daily_rate * v_days;
      v_done := v_elapsed_days >= v_inv.duration_days;
      v_principal_return := case when v_done then v_inv.principal else 0 end;
      v_total := v_total + v_profit;

      if v_inv.currency = 'BDX' then
        update public.user_profile
        set bdx_balance = bdx_balance + v_profit + v_principal_return,
            locked_bdx_balance = case when v_done then greatest(0,locked_bdx_balance-v_inv.principal) else locked_bdx_balance end,
            updated_at = now()
        where user_id = v_uid;
      else
        update public.user_profile
        set available_balance = available_balance + v_profit + v_principal_return,
            locked_balance = case when v_done then greatest(0,locked_balance-v_inv.principal) else locked_balance end,
            updated_at = now()
        where user_id = v_uid;
      end if;

      update public.user_investment
      set credited_profit = credited_profit + v_profit,
          last_accrual_at = least(v_inv.started_at + make_interval(days => v_inv.duration_days), v_now),
          status = case when v_done then 'completed' else 'active' end,
          completed_at = case when v_done then v_now else completed_at end,
          updated_at = now()
      where id = v_inv.id;

      insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
      values(v_uid,'bonus',v_profit,v_inv.currency,'completed','approved',
        case when v_done then 'Plan maturity' else 'Daily interest' end,
        'Server-side investment profit');

      if v_done then
        insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
        values(v_uid,'bonus',v_inv.principal,v_inv.currency,'completed','approved',
          'Plan maturity','Investment principal returned');
      end if;
    end if;
  end loop;
  return v_total;
end;
$function$;

revoke all on function public.accrue_user_investments(uuid) from public, anon;
grant execute on function public.accrue_user_investments(uuid) to authenticated;

commit;
