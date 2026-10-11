begin;

-- The published plan ROI is a DAILY simple-interest rate, not total ROI
-- over the whole duration. This affects new investments created after this
-- migration. Existing user_investment rows retain their snapshotted rates;
-- do not silently reprice historical accruals or alter financial balances.
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

commit;
