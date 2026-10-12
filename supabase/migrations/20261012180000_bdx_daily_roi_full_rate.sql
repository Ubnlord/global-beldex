begin;

-- Published plan rates are DAILY ROI percentages. For each full 24-hour
-- accrual period, profit = BDX principal * daily ROI. Example: 4,000 BDX * 1.9%
-- = 76 BDX for GNS. Do not reinterpret these rates as total-term ROI.
-- Preserve historical USD investment snapshots and all previously credited profit.
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
 where id in ('gns','build','follow','apex','edifex','dixon','falcon');

-- Existing active BDX investments adopt the corrected daily rate for future
-- accruals only. Never change already credited profit, start times, or USD rows.
update public.user_investment ui
   set daily_rate = pc.daily_rate,
       updated_at = now()
  from public.investment_plan_catalog pc
 where pc.id = ui.plan_id
   and ui.currency = 'BDX'
   and ui.status = 'active'
   and ui.daily_accrual_enabled = true
   and ui.plan_id in ('gns','build','follow','apex','edifex','dixon','falcon')
   and ui.daily_rate is distinct from pc.daily_rate;

commit;
