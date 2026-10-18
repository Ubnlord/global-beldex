-- Manual admin daily profit follows the published daily-rate business rule.
-- Example: 4,000 BDX * 0.019 = 76 BDX per manual credit.
CREATE OR REPLACE FUNCTION public.admin_add_daily_investment_profit(p_user_id uuid, p_reason text)
RETURNS TABLE(credited_investments integer, credited_amount numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_admin public.admin_user;
  v_inv public.user_investment;
  v_profile public.user_profile;
  v_profit numeric;
  v_date date := (now() at time zone 'utc')::date;
  v_count integer := 0;
  v_total numeric := 0;
  v_daily_id uuid;
  v_tx public.transaction;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if not public.is_admin()
     or not (public.admin_has_permission('manage_users') or public.admin_has_permission('manage_investments')) then
    raise exception 'Permission denied';
  end if;
  if p_user_id is null then raise exception 'User is required'; end if;
  if v_reason is null then raise exception 'Reason is required'; end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_profile from public.user_profile where user_id=p_user_id for update;
  if v_profile.user_id is null then raise exception 'User profile not found'; end if;
  if coalesce(v_profile.blocked,false) then raise exception 'Blocked accounts cannot receive manual daily profit'; end if;

  for v_inv in
    select * from public.user_investment
    where user_id=p_user_id and status='active' and daily_accrual_enabled=true
      and currency='BDX' and duration_days > 0
    order by id
    for update
  loop
    -- Business rule: daily profit is principal multiplied by the stored plan rate.
    v_profit := round(v_inv.principal * v_inv.daily_rate, 18);
    if v_profit <= 0 then continue; end if;

    v_daily_id := null;
    insert into public.admin_daily_investment_profit(
      investment_id,user_id,profit_date,profit_amount,currency,admin_user_id,reason
    ) values (
      v_inv.id,p_user_id,v_date,v_profit,'BDX',auth.uid(),v_reason
    )
    on conflict (investment_id,profit_date) do nothing
    returning id into v_daily_id;
    if v_daily_id is null then continue; end if;

    update public.user_profile
       set bdx_balance=bdx_balance+v_profit,updated_at=now()
     where user_id=p_user_id;

    update public.user_investment
       set credited_profit=credited_profit+v_profit,updated_at=now()
     where id=v_inv.id;

    insert into public.transaction(
      user_id,type,amount,currency,status,approval_status,method,note,
      approved_by,approval_reason,approved_at,settled_at
    ) values (
      p_user_id,'bonus',v_profit,'BDX','completed','approved',
      'Admin daily investment profit',
      'Manually credited one day of investment profit for '||v_date::text,
      v_admin.id,v_reason,now(),now()
    ) returning * into v_tx;

    update public.admin_daily_investment_profit set transaction_id=v_tx.id where id=v_daily_id;

    insert into public.admin_action_audit(
      admin_id,user_id,action,target_id,old_values,new_values,reason
    ) values (
      v_admin.id,p_user_id,'daily_investment_profit_added',v_inv.id,
      jsonb_build_object('credited_profit',v_inv.credited_profit,'currency','BDX'),
      jsonb_build_object('daily_profit',v_profit,'profit_date',v_date,'currency','BDX','transaction_id',v_tx.id),
      v_reason
    );

    v_count := v_count + 1;
    v_total := v_total + v_profit;
  end loop;

  return query select v_count,v_total;
end;
$function$;
REVOKE ALL ON FUNCTION public.admin_add_daily_investment_profit(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_add_daily_investment_profit(uuid,text) TO authenticated;
