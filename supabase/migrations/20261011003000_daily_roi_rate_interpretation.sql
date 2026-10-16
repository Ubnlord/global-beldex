begin;

-- Published ROI values are total simple-interest ROI over the full plan term,
-- not daily rates. Divide each published total by its duration to obtain the
-- daily accrual rate used by accrue_user_investments().
-- Existing investment snapshots are intentionally left untouched so a rate
-- correction cannot be retroactively applied to elapsed accrual periods.
update public.investment_plan_catalog
   set daily_rate = case id
     when 'gns' then 0.019::numeric / duration_days
     when 'build' then 0.0251::numeric / duration_days
     when 'follow' then 0.0392::numeric / duration_days
     when 'apex' then 0.0856::numeric / duration_days
     when 'edifex' then 0.1343::numeric / duration_days
     when 'dixon' then 0.1543::numeric / duration_days
     when 'falcon' then 0.2378::numeric / duration_days
     else daily_rate
   end,
   updated_at = now()
 where id in ('gns','build','follow','apex','edifex','dixon','falcon')
   and duration_days > 0;

commit;
