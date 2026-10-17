begin;

-- Restore the published plan catalogue when replaying a schema-only baseline.
-- Existing rows keep their configured names, limits, and active flags; only
-- missing plan IDs are inserted. Rates below implement the published TOTAL ROI
-- over each plan's full duration, as documented in src/lib/platform/catalog.ts.
insert into public.investment_plan_catalog
  (id, name, min_amount, max_amount, duration_days, daily_rate, active)
values
  ('gns',    'GNS PLAN',       4000,   10000,  30, 0.019::numeric / 30,   true),
  ('build',  'BUILD UP PLAN', 11000,   16000,  60, 0.0251::numeric / 60,  true),
  ('follow', 'FOLLOW UP PLAN',17000,   30000,  60, 0.0392::numeric / 60, true),
  ('apex',   'APEX PLAN',     40000,   80000, 365, 0.0856::numeric / 365,true),
  ('edifex', 'EDIFEX PLAN',   90000,  150000, 730, 0.1343::numeric / 730,true),
  ('dixon',  'DIXON PLAN',   160000,  220000, 730, 0.1543::numeric / 730,true),
  ('falcon', 'FALCON PLAN',  220000, 1000000,1825, 0.2378::numeric / 1825,true)
on conflict (id) do nothing;

update public.investment_plan_catalog
set daily_rate = case id
  when 'gns' then 0.019::numeric / 30
  when 'build' then 0.0251::numeric / 60
  when 'follow' then 0.0392::numeric / 60
  when 'apex' then 0.0856::numeric / 365
  when 'edifex' then 0.1343::numeric / 730
  when 'dixon' then 0.1543::numeric / 730
  when 'falcon' then 0.2378::numeric / 1825
  else daily_rate
end,
updated_at = now()
where id in ('gns','build','follow','apex','edifex','dixon','falcon');

do $assert_catalog$
begin
  if (select count(*) from public.investment_plan_catalog
      where id in ('gns','build','follow','apex','edifex','dixon','falcon')) <> 7 then
    raise exception 'Published investment plan catalogue is incomplete';
  end if;

  if exists (
    select 1 from public.investment_plan_catalog p
    where p.id in ('gns','build','follow','apex','edifex','dixon','falcon')
      and abs(p.daily_rate - case p.id
        when 'gns' then 0.019::numeric / 30
        when 'build' then 0.0251::numeric / 60
        when 'follow' then 0.0392::numeric / 60
        when 'apex' then 0.0856::numeric / 365
        when 'edifex' then 0.1343::numeric / 730
        when 'dixon' then 0.1543::numeric / 730
        when 'falcon' then 0.2378::numeric / 1825
      end) > 0.000000000000000001
  ) then
    raise exception 'Plan catalogue daily rates do not match published total ROI divided by duration';
  end if;
end;
$assert_catalog$;

-- Admin mutation RPCs must not be callable by anonymous clients.
revoke all on function public.admin_approve_deposit(uuid,text) from public, anon;
revoke all on function public.admin_reject_deposit(uuid,text) from public, anon;
revoke all on function public.admin_approve_withdrawal(uuid,text) from public, anon;
revoke all on function public.admin_reject_withdrawal(uuid,text) from public, anon;
grant execute on function public.admin_approve_deposit(uuid,text) to authenticated;
grant execute on function public.admin_reject_deposit(uuid,text) to authenticated;
grant execute on function public.admin_approve_withdrawal(uuid,text) to authenticated;
grant execute on function public.admin_reject_withdrawal(uuid,text) to authenticated;

-- Browser clients must use authorized RPCs rather than mutate financial or
-- audit tables directly. RLS remains an additional defense, not a substitute
-- for removing table write grants.
revoke insert, update on table public.user_profile from public, anon, authenticated;
revoke insert, update on table public.transaction from public, anon, authenticated;
revoke insert, update on table public.user_investment from public, anon, authenticated;
revoke insert, update on table public.admin_action_audit from public, anon, authenticated;
revoke insert, update on table public.transaction_audit from public, anon, authenticated;

commit;
