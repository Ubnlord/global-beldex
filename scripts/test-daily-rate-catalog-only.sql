-- Regression for the catalog-only daily ROI interpretation migration.
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

create temporary table _daily_rate_snapshot_before as
select id,daily_rate,principal,duration_days,started_at,last_accrual_at,
       credited_profit,status,currency,daily_accrual_enabled
from public.user_investment
where user_id='a1200000-0000-4000-8000-000000000001';

\i ../supabase/migrations/20261011003000_daily_roi_rate_interpretation.sql

do $check$
begin
  if exists (
    (select id,daily_rate,principal,duration_days,started_at,last_accrual_at,
            credited_profit,status,currency,daily_accrual_enabled
       from public.user_investment
      where user_id='a1200000-0000-4000-8000-000000000001')
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
      where user_id='a1200000-0000-4000-8000-000000000001')
  ) then
    raise exception 'Catalog rate migration changed a historical investment snapshot';
  end if;

  if (select daily_rate from public.investment_plan_catalog where id='gns')
       <> round(0.019::numeric / 30,18) then
    raise exception 'GNS catalog rate does not equal published total ROI divided by duration';
  end if;
  if (select daily_rate from public.investment_plan_catalog where id='apex')
       <> round(0.0856::numeric / 365,18) then
    raise exception 'APEX catalog rate does not equal published total ROI divided by duration';
  end if;
end;
$check$;

delete from public.user_investment where user_id='a1200000-0000-4000-8000-000000000001';
delete from public.user_profile where user_id='a1200000-0000-4000-8000-000000000001';
delete from auth.users where id='a1200000-0000-4000-8000-000000000001';
