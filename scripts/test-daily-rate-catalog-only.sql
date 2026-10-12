-- Regression for the daily ROI correction, including active BDX investments and untouched USD snapshots.
-- Execute only in the disposable local Supabase CI database, never against production.
\set ON_ERROR_STOP on

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a1200000-0000-4000-8000-000000000001','authenticated','authenticated',
  'daily-rate-catalog-fixture@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()
) on conflict (id) do nothing;

insert into public.user_profile(user_id,available_balance,bdx_balance)
values ('a1200000-0000-4000-8000-000000000001',123,456)
on conflict (user_id) do nothing;

-- Deliberately use a sentinel historical snapshot that differs from the catalog.
insert into public.user_investment(
  user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,
  credited_profit,status,currency,daily_accrual_enabled
) values (
  'a1200000-0000-4000-8000-000000000001','gns',1000,0.0123456789,30,
  now()-interval '3 days',now()-interval '1 day',7.25,'active','USD',true
);

insert into public.user_investment(
  user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,
  credited_profit,status,currency,daily_accrual_enabled
) values (
  'a1200000-0000-4000-8000-000000000001','gns',4000,round(0.019::numeric / 30,18),30,
  now()-interval '3 days',now()-interval '1 day',7.25,'active','BDX',true
);

create temporary table _daily_rate_snapshot_before as
select id,daily_rate,principal,duration_days,started_at,last_accrual_at,
       credited_profit,status,currency,daily_accrual_enabled
from public.user_investment
where user_id='a1200000-0000-4000-8000-000000000001' and currency='USD';

\i ../supabase/migrations/20261011003000_daily_roi_rate_interpretation.sql
\i ../supabase/migrations/20261012180000_bdx_daily_roi_full_rate.sql

do $check$
begin
  if exists (
    (select id,daily_rate,principal,duration_days,started_at,last_accrual_at,
            credited_profit,status,currency,daily_accrual_enabled
       from public.user_investment
      where user_id='a1200000-0000-4000-8000-000000000001' and currency='USD')
    except
    (select id,daily_rate,principal,duration_days,started_at,last_accrual_at,
            credited_profit,status,currency,daily_accrual_enabled
       from _daily_rate_snapshot_before)
  ) or exists (
    (select id,daily_rate,principal,duration_days,started_at,last_accrual_at,
            credited_profit,status,currency,daily_accrual_enabled
       from _daily_rate_snapshot_before)
    except
    (select id,daily_rate,principal,duration_days,started_at,last_accrual_at,
            credited_profit,status,currency,daily_accrual_enabled
       from public.user_investment
      where user_id='a1200000-0000-4000-8000-000000000001' and currency='USD')
  ) then
    raise exception 'Catalog rate migration changed a historical investment snapshot';
  end if;

  if (select daily_rate from public.investment_plan_catalog where id='gns') <> 0.019::numeric then
    raise exception 'GNS catalog rate is not the full daily ROI';
  end if;
  if (select daily_rate from public.investment_plan_catalog where id='apex') <> 0.0856::numeric then
    raise exception 'APEX catalog rate is not the full daily ROI';
  end if;
  if (select daily_rate from public.user_investment
       where user_id='a1200000-0000-4000-8000-000000000001' and currency='BDX') <> 0.019::numeric then
    raise exception 'Active BDX investment was not upgraded to the full daily ROI';
  end if;
  if (select credited_profit from public.user_investment
       where user_id='a1200000-0000-4000-8000-000000000001' and currency='BDX') <> 7.25 then
    raise exception 'Rate upgrade must not rewrite historical credited profit';
  end if;
end;
$check$;

delete from public.user_investment where user_id='a1200000-0000-4000-8000-000000000001';
delete from public.user_profile where user_id='a1200000-0000-4000-8000-000000000001';
delete from auth.users where id='a1200000-0000-4000-8000-000000000001';
