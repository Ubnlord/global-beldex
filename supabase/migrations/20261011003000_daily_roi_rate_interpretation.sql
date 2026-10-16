begin;

-- Published ROI values are daily simple-interest rates, exactly as shown on
-- the plan cards. Profit = principal * daily_rate * elapsed_days. This is not
-- compound interest; active investment snapshots are not retroactively changed.
-- Existing investment snapshots are intentionally left untouched so a rate
-- correction cannot be retroactively applied to elapsed accrual periods.
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

commit;
