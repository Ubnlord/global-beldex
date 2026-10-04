-- Milestone 2: server-authoritative investment, profit, swap and referral ledger
-- Apply after 0001_admin_and_transactions.sql.

create table if not exists public.investment_plan_catalog (
  id text primary key,
  name text not null,
  min_amount numeric(38,18) not null check (min_amount > 0),
  max_amount numeric(38,18),
  duration_days integer not null check (duration_days > 0),
  daily_rate numeric(38,18) not null check (daily_rate >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_investment (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id text not null references public.investment_plan_catalog(id),
  principal numeric(38,18) not null check (principal > 0),
  daily_rate numeric(38,18) not null check (daily_rate >= 0),
  duration_days integer not null check (duration_days > 0),
  started_at timestamptz not null default now(),
  last_accrual_at timestamptz not null default now(),
  credited_profit numeric(38,18) not null default 0,
  status text not null default 'active' check (status in ('active','completed','cancelled')),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_profile
  add column if not exists bdx_balance numeric(38,18) not null default 0,
  add column if not exists referral_code text,
  add column if not exists referred_by_user_id uuid references auth.users(id),
  add column if not exists referral_earnings numeric(38,18) not null default 0;

create unique index if not exists user_profile_referral_code_uq
  on public.user_profile(referral_code) where referral_code is not null;
create index if not exists user_investment_user_status_idx on public.user_investment(user_id,status);
create index if not exists user_investment_due_idx on public.user_investment(status,last_accrual_at);
create index if not exists user_investment_plan_id_idx on public.user_investment(plan_id);
create index if not exists user_profile_referred_by_user_id_idx on public.user_profile(referred_by_user_id);

insert into public.investment_plan_catalog(id,name,min_amount,max_amount,duration_days,daily_rate) values
('gns','GNS PLAN',4000,10000,30,0.0019/30),
('build','BUILD UP PLAN',11000,16000,60,0.0251/60),
('follow','FOLLOW UP PLAN',17000,30000,60,0.0392/60),
('apex','APEX PLAN',40000,80000,365,0.0856/365),
('edifex','EDIFEX PLAN',90000,150000,730,0.1343/730),
('dixon','DIXON PLAN',160000,220000,730,0.1543/730),
('falcon','FALCON PLAN',220000,1000000,1825,0.2378/1825)
on conflict(id) do update set name=excluded.name,min_amount=excluded.min_amount,
max_amount=excluded.max_amount,duration_days=excluded.duration_days,
daily_rate=excluded.daily_rate,updated_at=now();

alter table public.investment_plan_catalog enable row level security;
alter table public.user_investment enable row level security;

drop policy if exists investment_catalog_read on public.investment_plan_catalog;
create policy investment_catalog_read on public.investment_plan_catalog
for select to authenticated using (active or is_admin());

drop policy if exists investments_select on public.user_investment;
create policy investments_select on public.user_investment
for select to authenticated using ((select auth.uid())=user_id or is_admin());

drop policy if exists investments_insert on public.user_investment;
create policy investments_insert on public.user_investment
for insert to authenticated with check ((select auth.uid())=user_id);

drop policy if exists investments_update_admin on public.user_investment;
create policy investments_update_admin on public.user_investment
for update to authenticated using (is_admin()) with check (is_admin());

drop policy if exists transactions_insert_own on public.transaction;
drop policy if exists transactions_insert_admin_referral on public.transaction;
create policy transactions_insert on public.transaction
for insert to authenticated
with check (
  (select auth.uid())=user_id
  or (is_admin() and type='referral' and coalesce(method,'') like 'Referral deposit %')
);

create or replace function public.ensure_user_profile(
  p_username text,p_fullname text,p_phone text default '',p_country text default '',p_ref text default null
) returns public.user_profile language plpgsql security invoker set search_path=public as $$
declare
 v_uid uuid:=auth.uid(); v_profile public.user_profile; v_ref uuid; v_code text;
begin
 if v_uid is null then raise exception 'Unauthorized'; end if;
 if coalesce(trim(p_username),'')='' then raise exception 'Username is required'; end if;
 if p_ref is not null and trim(p_ref)<>'' then
   select user_id into v_ref from public.user_profile
   where lower(username)=lower(trim(p_ref)) or lower(coalesce(referral_code,''))=lower(trim(p_ref)) limit 1;
   if v_ref=v_uid then raise exception 'Cannot refer yourself'; end if;
 end if;
 v_code:=lower(regexp_replace(trim(p_username),'[^a-zA-Z0-9_-]','','g'));
 if v_code='' then v_code:=substr(replace(v_uid::text,'-',''),1,12); end if;
 insert into public.user_profile(user_id,username,fullname,phone,country,referral_code,referred_by_user_id,available_balance,updated_at)
 values(v_uid,trim(p_username),coalesce(nullif(trim(p_fullname),''),trim(p_username)),coalesce(p_phone,''),coalesce(p_country,''),v_code,v_ref,3,now())
 on conflict(user_id) do update set username=coalesce(nullif(excluded.username,''),public.user_profile.username),
 fullname=coalesce(nullif(excluded.fullname,''),public.user_profile.fullname),phone=excluded.phone,country=excluded.country,
 referral_code=coalesce(public.user_profile.referral_code,excluded.referral_code),
 referred_by_user_id=coalesce(public.user_profile.referred_by_user_id,excluded.referred_by_user_id),updated_at=now()
 returning * into v_profile;
 if not exists(select 1 from public.transaction where user_id=v_uid and type='bonus' and method='Welcome Bonus') then
   insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
   values(v_uid,'bonus',3,'completed','approved','Welcome Bonus','Server-side welcome bonus');
 end if;
 return v_profile;
end; $$;

create or replace function public.buy_investment_plan(p_plan_id text,p_amount numeric)
returns public.user_investment language plpgsql security invoker set search_path=public as $$
declare
 v_uid uuid:=auth.uid(); v_plan public.investment_plan_catalog; v_profile public.user_profile; v_inv public.user_investment;
begin
 if v_uid is null then raise exception 'Unauthorized'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
 select * into v_plan from public.investment_plan_catalog where id=p_plan_id and active;
 if v_plan.id is null then raise exception 'Investment plan not found'; end if;
 if p_amount<v_plan.min_amount then raise exception 'Minimum investment is %',v_plan.min_amount; end if;
 if v_plan.max_amount is not null and p_amount>v_plan.max_amount then raise exception 'Maximum investment is %',v_plan.max_amount; end if;
 select * into v_profile from public.user_profile where user_id=v_uid for update;
 if v_profile.user_id is null then raise exception 'Profile not found'; end if;
 if v_profile.available_balance<p_amount then raise exception 'Insufficient balance'; end if;
 update public.user_profile set available_balance=available_balance-p_amount,locked_balance=locked_balance+p_amount,updated_at=now() where user_id=v_uid;
 insert into public.user_investment(user_id,plan_id,principal,daily_rate,duration_days)
 values(v_uid,v_plan.id,p_amount,v_plan.daily_rate,v_plan.duration_days) returning * into v_inv;
 insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
 values(v_uid,'plan',p_amount,'completed','approved',v_plan.name,'Investment plan purchase');
 return v_inv;
end; $$;

create or replace function public.accrue_user_investments(p_user_id uuid default auth.uid())
returns numeric language plpgsql security invoker set search_path=public as $$
declare
 v_uid uuid:=coalesce(p_user_id,auth.uid()); v_inv public.user_investment; v_now timestamptz:=now();
 v_elapsed_days integer; v_previous_days integer; v_days integer; v_profit numeric; v_total numeric:=0; v_done boolean;
begin
 if v_uid is null then raise exception 'Unauthorized'; end if;
 if v_uid<>auth.uid() then raise exception 'Forbidden'; end if;
 for v_inv in select * from public.user_investment where user_id=v_uid and status='active' order by created_at for update loop
   v_elapsed_days:=least(v_inv.duration_days,greatest(0,floor(extract(epoch from(v_now-v_inv.started_at))/86400)::integer));
   v_previous_days:=least(v_inv.duration_days,greatest(0,floor(extract(epoch from(v_inv.last_accrual_at-v_inv.started_at))/86400)::integer));
   v_days:=greatest(0,v_elapsed_days-v_previous_days);
   if v_days>0 then
     v_profit:=v_inv.principal*v_inv.daily_rate*v_days; v_total:=v_total+v_profit; v_done:=v_elapsed_days>=v_inv.duration_days;
     update public.user_profile set available_balance=available_balance+v_profit,
       locked_balance=case when v_done then greatest(0,locked_balance-v_inv.principal) else locked_balance end,updated_at=now() where user_id=v_uid;
     update public.user_investment set credited_profit=credited_profit+v_profit,
       last_accrual_at=least(v_inv.started_at+make_interval(days=>v_inv.duration_days),v_now),
       status=case when v_done then 'completed' else 'active' end,
       completed_at=case when v_done then v_now else completed_at end,updated_at=now() where id=v_inv.id;
     insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
     values(v_uid,'bonus',v_profit,'completed','approved',case when v_done then 'Plan maturity' else 'Daily interest' end,'Server-side investment profit');
   end if;
 end loop;
 return v_total;
end; $$;

create or replace function public.swap_assets(p_from text,p_to text,p_amount numeric,p_rate numeric)
returns public.transaction language plpgsql security invoker set search_path=public as $$
declare
 v_uid uuid:=auth.uid(); v_profile public.user_profile; v_out numeric; v_tx public.transaction;
begin
 if v_uid is null then raise exception 'Unauthorized'; end if;
 if p_from not in('USD','BDX') or p_to not in('USD','BDX') or p_from=p_to then raise exception 'Invalid swap pair'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
 if p_rate is null or p_rate<=0 then raise exception 'Invalid rate'; end if;
 select * into v_profile from public.user_profile where user_id=v_uid for update;
 if v_profile.user_id is null then raise exception 'Profile not found'; end if;
 if p_from='USD' then
   if v_profile.available_balance<p_amount then raise exception 'Insufficient USD balance'; end if;
   v_out:=p_amount/p_rate;
   update public.user_profile set available_balance=available_balance-p_amount,bdx_balance=bdx_balance+v_out,updated_at=now() where user_id=v_uid;
   insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
   values(v_uid,'swap',p_amount,'completed','approved','USD → BDX',p_amount::text||' USD → '||round(v_out,4)::text||' BDX') returning * into v_tx;
 else
   if v_profile.bdx_balance<p_amount then raise exception 'Insufficient BDX balance'; end if;
   v_out:=p_amount*p_rate;
   update public.user_profile set bdx_balance=bdx_balance-p_amount,available_balance=available_balance+v_out,updated_at=now() where user_id=v_uid;
   insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
   values(v_uid,'swap',v_out,'completed','approved','BDX → USD',p_amount::text||' BDX → '||round(v_out,2)::text||' USD') returning * into v_tx;
 end if;
 return v_tx;
end; $$;

create or replace function public.credit_referral_for_deposit(p_transaction_id uuid)
returns numeric language plpgsql security invoker set search_path=public as $$
declare v_tx public.transaction; v_ref uuid; v_cut numeric;
begin
 select * into v_tx from public.transaction where id=p_transaction_id for update;
 if v_tx.id is null then raise exception 'Transaction not found'; end if;
 if v_tx.type<>'deposit' or v_tx.status<>'completed' then return 0; end if;
 select referred_by_user_id into v_ref from public.user_profile where user_id=v_tx.user_id;
 if v_ref is null then return 0; end if;
 if exists(select 1 from public.transaction where method='Referral deposit '||v_tx.id::text) then return 0; end if;
 v_cut:=round(v_tx.amount*0.10,18); if v_cut<=0 then return 0; end if;
 update public.user_profile set available_balance=available_balance+v_cut,referral_earnings=referral_earnings+v_cut,updated_at=now() where user_id=v_ref;
 insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
 values(v_ref,'referral',v_cut,'completed','approved','Referral deposit '||v_tx.id::text,'10% referral commission');
 return v_cut;
end; $$;

create or replace function public.admin_settle_transaction(p_transaction_id uuid,p_reason text default null)
returns public.transaction language plpgsql security invoker set search_path=public as $
declare v_admin public.admin_user; v_tx public.transaction;
begin
 select * into v_admin from public.admin_user where user_id=auth.uid();
 if v_admin.id is null then raise exception 'Admin access required'; end if;
 select * into v_tx from public.transaction where id=p_transaction_id for update;
 if v_tx.id is null then raise exception 'Transaction not found'; end if;
 if v_tx.type not in('deposit','withdraw') then raise exception 'Only deposit and withdrawal can be settled'; end if;
 if v_tx.status='completed' then raise exception 'Transaction already completed'; end if;
 if v_tx.approval_status<>'approved' then raise exception 'Transaction must be approved first'; end if;
 if v_tx.type='deposit' then
   update public.user_profile set available_balance=available_balance+v_tx.amount,total_deposits=total_deposits+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
 else
   update public.user_profile set total_withdrawals=total_withdrawals+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
 end if;
 update public.transaction set status='completed',settled_at=now(),updated_at=now() where id=p_transaction_id returning * into v_tx;
 if v_tx.type='deposit' then perform public.credit_referral_for_deposit(v_tx.id); end if;
 insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
 values(v_tx.id,v_admin.id,'settled',jsonb_build_object('status','pending'),jsonb_build_object('status',v_tx.status),p_reason);
 return v_tx;
end; $;

grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;

grant execute on function public.ensure_user_profile(text,text,text,text,text) to authenticated;
grant execute on function public.buy_investment_plan(text,numeric) to authenticated;
grant execute on function public.accrue_user_investments(uuid) to authenticated;
grant execute on function public.swap_assets(text,text,numeric,numeric) to authenticated;
grant execute on function public.credit_referral_for_deposit(uuid) to authenticated;
revoke execute on function public.ensure_user_profile(text,text,text,text,text) from anon;
revoke execute on function public.buy_investment_plan(text,numeric) from anon;
revoke execute on function public.accrue_user_investments(uuid) from anon;
revoke execute on function public.swap_assets(text,text,numeric,numeric) from anon;
revoke execute on function public.credit_referral_for_deposit(uuid) from anon;
