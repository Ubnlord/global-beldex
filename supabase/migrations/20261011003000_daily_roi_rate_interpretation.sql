begin;

-- Published plan ROI is the total simple-interest return over the plan duration,
-- not a daily rate. Store the per-day fraction used by accrue_user_investments:
-- profit = principal * daily_rate * elapsed_days.
-- Keep existing user_investment.daily_rate snapshots untouched; this catalogue
-- controls new purchases only. Historical corrections are handled separately by
-- the earlier rate-correction migrations and must not be replayed here.
update public.investment_plan_catalog
   set daily_rate = case id
     when 'gns' then round(0.019::numeric / 30, 18)
     when 'build' then round(0.0251::numeric / 60, 18)
     when 'follow' then round(0.0392::numeric / 60, 18)
     when 'apex' then round(0.0856::numeric / 365, 18)
     when 'edifex' then round(0.1343::numeric / 730, 18)
     when 'dixon' then round(0.1543::numeric / 730, 18)
     when 'falcon' then round(0.2378::numeric / 1825, 18)
     else daily_rate
   end,
   updated_at = now()
 where id in ('gns','build','follow','apex','edifex','dixon','falcon');

commit;
