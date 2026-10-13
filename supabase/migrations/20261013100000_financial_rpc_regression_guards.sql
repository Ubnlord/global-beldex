begin;

-- Remove the unsafe legacy overload. The six-argument currency-aware RPC has
-- p_currency defaulted, so legacy five-argument callers resolve to that
-- implementation and receive its request-ID consistency checks.
drop function if exists public.create_financial_transaction(text,numeric,text,text,uuid);

-- Keep investment principal in the same denomination as its wallet. The prior
-- implementation always moved principal through the USD columns, even for BDX
-- investments. This correction does not rewrite existing financial records.
create or replace function public.admin_manage_investment(
  p_investment_id uuid,
  p_daily_rate numeric,
  p_status text,
  p_reason text
)
returns public.user_investment
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_inv public.user_investment;
  v_profile public.user_profile;
  v_admin public.admin_user;
  v_currency text;
  v_old_status text;
begin
  if auth.uid() is null or not public.is_admin()
     or not public.admin_has_permission('manage_users') then
    raise exception 'not authorized';
  end if;
  select * into v_admin from public.admin_user where user_id = auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if p_daily_rate is null or p_daily_rate < 0 then
    raise exception 'invalid daily rate';
  end if;
  if p_status not in ('active','completed','cancelled') then
    raise exception 'invalid investment status';
  end if;
  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'reason is required';
  end if;

  select * into v_inv
    from public.user_investment
   where id = p_investment_id
   for update;
  if not found then raise exception 'investment not found'; end if;
  v_old_status := v_inv.status;
  v_currency := coalesce(v_inv.currency,'USD');
  if v_currency not in ('USD','BDX') then
    raise exception 'unsupported investment currency';
  end if;

  select * into v_profile
    from public.user_profile
   where user_id = v_inv.user_id
   for update;
  if not found then raise exception 'user profile not found'; end if;
  if v_profile.blocked then
    raise exception 'blocked user cannot have investment managed';
  end if;

  if v_old_status = 'active' and p_status in ('completed','cancelled') then
    if v_currency = 'BDX' then
      update public.user_profile
         set locked_bdx_balance = locked_bdx_balance - v_inv.principal,
             bdx_balance = bdx_balance + v_inv.principal,
             updated_at = now()
       where user_id = v_inv.user_id
         and locked_bdx_balance >= v_inv.principal;
    else
      update public.user_profile
         set locked_balance = locked_balance - v_inv.principal,
             available_balance = available_balance + v_inv.principal,
             updated_at = now()
       where user_id = v_inv.user_id
         and locked_balance >= v_inv.principal;
    end if;
    if not found then
      raise exception 'locked balance is below investment principal';
    end if;
  elsif v_old_status in ('completed','cancelled') and p_status = 'active' then
    if v_currency = 'BDX' then
      update public.user_profile
         set bdx_balance = bdx_balance - v_inv.principal,
             locked_bdx_balance = locked_bdx_balance + v_inv.principal,
             updated_at = now()
       where user_id = v_inv.user_id
         and bdx_balance >= v_inv.principal;
    else
      update public.user_profile
         set available_balance = available_balance - v_inv.principal,
             locked_balance = locked_balance + v_inv.principal,
             updated_at = now()
       where user_id = v_inv.user_id
         and available_balance >= v_inv.principal;
    end if;
    if not found then
      raise exception 'insufficient available balance for investment currency';
    end if;
  end if;

  update public.user_investment
     set daily_rate = p_daily_rate,
         status = p_status,
         completed_at = case
           when p_status in ('completed','cancelled') then coalesce(completed_at, now())
           else null
         end,
         updated_at = now()
   where id = p_investment_id
  returning * into v_inv;

  insert into public.admin_action_audit
    (admin_id, user_id, action, target_id, old_values, new_values, reason, created_at)
  values
    (v_admin.id, v_inv.user_id, 'manage_investment', v_inv.id,
     jsonb_build_object('status', v_old_status, 'currency', v_currency),
     jsonb_build_object('status', v_inv.status, 'daily_rate', v_inv.daily_rate, 'currency', v_currency),
     btrim(p_reason), now());

  return v_inv;
end;
$function$;

revoke all on function public.admin_manage_investment(uuid,numeric,text,text) from public, anon;
grant execute on function public.admin_manage_investment(uuid,numeric,text,text) to authenticated, service_role;

commit;
