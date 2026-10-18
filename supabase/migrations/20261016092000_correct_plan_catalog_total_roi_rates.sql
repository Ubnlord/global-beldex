begin;

-- Forward correction to enforce the published plan-card policy: the listed percentage is the daily simple-interest rate. This updates only the catalogue for new investments. Existing investment snapshots, credited profits, balances,
-- and ledger rows are not rewritten.
update public.investment_plan_catalog
   set daily_rate = case id
     when 'gns' then 0.019::numeric
     when 'build' then 0.0251::numeric
     when 'follow' then 0.0392::numeric
     when 'apex' then 0.0856::numeric
     when 'edifex' then 0.1343::numeric
     when 'dixon' then 0.1543::numeric
     when 'falcon' then 0.2378::numeric
     else daily_rate
   end,
   updated_at = now()
 where id in ('gns','build','follow','apex','edifex','dixon','falcon')
   and duration_days > 0;

do $assert_catalog_rates$
begin
  if exists (
    select 1
    from public.investment_plan_catalog p
    where p.id in ('gns','build','follow','apex','edifex','dixon','falcon')
      and p.duration_days > 0
      and abs(p.daily_rate - case p.id
        when 'gns' then 0.019::numeric
        when 'build' then 0.0251::numeric
        when 'follow' then 0.0392::numeric
        when 'apex' then 0.0856::numeric
        when 'edifex' then 0.1343::numeric
        when 'dixon' then 0.1543::numeric
        when 'falcon' then 0.2378::numeric
      end) > 0.000000000000000001
  ) then
    raise exception 'Plan catalogue daily rates do not match published daily ROI';
  end if;
end;
$assert_catalog_rates$;

commit;
