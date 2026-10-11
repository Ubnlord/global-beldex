begin;

-- Published ROI values are DAILY simple-interest rates, not total ROI over
-- the investment duration. This changes future accrual rates for active
-- investments. It does not retroactively recalculate credited profits or
-- change any user balance. Completed investments are left untouched.
update public.investment_plan_catalog
   set daily_rate = case id
     when 'gns' then 0.019
     when 'build' then 0.0251
     when 'follow' then 0.0392
     when 'apex' then 0.0856
     when 'edifex' then 0.1343
     when 'dixon' then 0.1543
     when 'falcon' then 0.2378
     else daily_rate
   end,
   updated_at = now()
 where id in ('gns','build','follow','apex','edifex','dixon','falcon');

-- Existing active stakes retain already credited earnings and balances.
-- Their stored rate is changed only for future accruals, without back-credit.
update public.user_investment
   set daily_rate = case plan_id
     when 'gns' then 0.019
     when 'build' then 0.0251
     when 'follow' then 0.0392
     when 'apex' then 0.0856
     when 'edifex' then 0.1343
     when 'dixon' then 0.1543
     when 'falcon' then 0.2378
     else daily_rate
   end,
   updated_at = now()
 where status = 'active'
   and plan_id in ('gns','build','follow','apex','edifex','dixon','falcon')
   and daily_accrual_enabled = true;

commit;
