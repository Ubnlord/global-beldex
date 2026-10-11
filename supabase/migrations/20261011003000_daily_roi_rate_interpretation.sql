begin;

-- Published ROI values are DAILY simple-interest rates, not total ROI over
-- the investment duration. This changes the plan catalogue used for new
-- purchases. Existing investment snapshots are intentionally left untouched:
-- changing an active rate without first settling its old-rate accrual could
-- apply the new rate to time elapsed before this migration.
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
