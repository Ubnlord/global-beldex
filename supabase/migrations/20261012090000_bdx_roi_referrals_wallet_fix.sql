begin;

-- Keep production's seven new BDX plans in sync with the advertised cards.
-- Existing USD investments and historical transactions are not rewritten.
update public.investment_plan_catalog
set
  min_amount = case id
    when 'gns' then 4000 when 'build' then 11000 when 'follow' then 17000
    when 'apex' then 40000 when 'edifex' then 90000 when 'dixon' then 160000
    when 'falcon' then 220000 else min_amount end,
  max_amount = case id
    when 'gns' then 10000 when 'build' then 16000 when 'follow' then 30000
    when 'apex' then 80000 when 'edifex' then 150000 when 'dixon' then 220000
    when 'falcon' then 1000000 else max_amount end,
  daily_rate = case id
    when 'gns' then 0.019 when 'build' then 0.0251 when 'follow' then 0.0392
    when 'apex' then 0.0856 when 'edifex' then 0.1343 when 'dixon' then 0.1543
    when 'falcon' then 0.2378 else daily_rate end,
  updated_at = now()
where id in ('gns','build','follow','apex','edifex','dixon','falcon');

alter table public.user_profile
  add column if not exists referral_earnings_bdx numeric(38,18) not null default 0;

comment on column public.user_profile.referral_earnings_bdx is
  'Completed BDX-denominated referral commissions, kept separate from USD referral earnings.';

create or replace function public.credit_referral_for_deposit(p_transaction_id uuid)
returns numeric
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_tx public.transaction;
  v_ref uuid;
  v_cut numeric;
  v_currency text;
begin
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if not found then raise exception 'Transaction not found'; end if;
  if v_tx.type <> 'deposit' or v_tx.status <> 'completed' then return 0; end if;

  v_currency := coalesce(v_tx.currency,'USD');
  if v_currency not in ('USD','BDX') then raise exception 'Unsupported referral currency'; end if;
  select referred_by_user_id into v_ref
    from public.user_profile where user_id=v_tx.user_id;
  if v_ref is null or v_ref=v_tx.user_id then return 0; end if;

  -- The referral marker makes retries on the same settled deposit idempotent.
  if exists(select 1 from public.transaction
            where type='referral' and method='Referral deposit '||v_tx.id::text) then
    return 0;
  end if;

  v_cut := round(v_tx.amount*0.10,18);
  if v_cut <= 0 then return 0; end if;

  if v_currency='BDX' then
    update public.user_profile
       set bdx_balance=bdx_balance+v_cut,
           referral_earnings_bdx=referral_earnings_bdx+v_cut,
           updated_at=now()
     where user_id=v_ref;
  else
    update public.user_profile
       set available_balance=available_balance+v_cut,
           referral_earnings=referral_earnings+v_cut,
           updated_at=now()
     where user_id=v_ref;
  end if;
  if not found then raise exception 'Referrer profile not found'; end if;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
  values(v_ref,'referral',v_cut,v_currency,'completed','approved',
         'Referral deposit '||v_tx.id::text,
         '10% referral commission for '||v_currency||' deposit');
  return v_cut;
end;
$function$;
revoke all on function public.credit_referral_for_deposit(uuid) from public, anon, authenticated;

create or replace function public.admin_settle_transaction(p_transaction_id uuid,p_reason text default null)
returns public.transaction
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
  v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if not found then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then
    raise exception 'Only deposit and withdrawal can be settled';
  end if;
  if v_tx.status='completed' then raise exception 'Transaction already completed'; end if;
  if v_tx.approval_status<>'approved' then
    raise exception 'Transaction must be approved first';
  end if;

  v_currency := coalesce(v_tx.currency,'USD');
  if v_currency not in ('USD','BDX') then raise exception 'Unsupported transaction currency'; end if;

  if v_tx.type='deposit' then
    if v_currency='BDX' then
      update public.user_profile
         set bdx_balance=bdx_balance+v_tx.amount,
             total_deposits_bdx=total_deposits_bdx+v_tx.amount,
             updated_at=now()
       where user_id=v_tx.user_id;
    else
      update public.user_profile
         set available_balance=available_balance+v_tx.amount,
             total_deposits=total_deposits+v_tx.amount,
             updated_at=now()
       where user_id=v_tx.user_id;
    end if;
  elsif v_currency='BDX' then
    update public.user_profile set total_withdrawals_bdx=total_withdrawals_bdx+v_tx.amount,
      updated_at=now() where user_id=v_tx.user_id;
  else
    update public.user_profile set total_withdrawals=total_withdrawals+v_tx.amount,
      updated_at=now() where user_id=v_tx.user_id;
  end if;
  if not found then raise exception 'User profile not found during settlement'; end if;

  update public.transaction set status='completed',settled_at=now(),updated_at=now()
    where id=p_transaction_id returning * into v_tx;

  if v_tx.type='deposit' then perform public.credit_referral_for_deposit(v_tx.id); end if;

  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'settled',jsonb_build_object('status','pending'),
         jsonb_build_object('status',v_tx.status,'currency',v_currency),p_reason);
  return v_tx;
end;
$function$;

revoke all on function public.admin_settle_transaction(uuid,text) from public,anon;
grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;

-- The admin user search uses separated currency totals so both wallets are visible.
create or replace function public.admin_search_users_bdx(p_query text default '',p_limit integer default 50)
returns table(user_id uuid,email text,username text,fullname text,phone text,country text,kyc_status text,available_balance numeric,locked_balance numeric,bdx_balance numeric,locked_bdx_balance numeric,total_deposits numeric,total_withdrawals numeric,referral_earnings numeric,blocked boolean,blocked_reason text,blocked_at timestamptz,created_at timestamptz)
language plpgsql security definer set search_path = ''
as $function$
declare v_query text := lower(trim(coalesce(p_query,''))); v_limit integer := greatest(1,least(coalesce(p_limit,50),100));
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then raise exception 'Permission denied'; end if;
  return query select p.user_id,u.email::text,p.username,p.fullname,p.phone,p.country,p.kyc_status,p.available_balance,p.locked_balance,p.bdx_balance,p.locked_bdx_balance,p.total_deposits,p.total_withdrawals,p.referral_earnings,p.blocked,p.blocked_reason,p.blocked_at,p.created_at
  from public.user_profile p join auth.users u on u.id=p.user_id
  where v_query='' or lower(coalesce(u.email,'')) like '%'||v_query||'%' or lower(coalesce(p.username,'')) like '%'||v_query||'%' or lower(coalesce(p.fullname,'')) like '%'||v_query||'%' or lower(coalesce(p.country,'')) like '%'||v_query||'%' or p.user_id::text like '%'||v_query||'%'
  order by p.created_at desc limit v_limit;
end;
$function$;
revoke all on function public.admin_search_users_bdx(text,integer) from public,anon;
grant execute on function public.admin_search_users_bdx(text,integer) to authenticated;

commit;
