begin;

-- Investment plan limits are stored in USD because user_profile.available_balance
-- and user_investment.principal are USD-denominated. The client displays and
-- collects plan amounts in BDX using the fixed platform quote:
-- 4,000 BDX = $293.984 USD (1 BDX = $0.073496 USD).
update public.investment_plan_catalog
set min_amount = case id
  when 'gns' then 293.984
  when 'build' then 808.456
  when 'follow' then 1249.432
  when 'apex' then 2939.840
  when 'edifex' then 6614.640
  when 'dixon' then 11759.360
  when 'falcon' then 16169.120
  else min_amount
end,
max_amount = case id
  when 'gns' then 734.960
  when 'build' then 1175.936
  when 'follow' then 2204.880
  when 'apex' then 5879.680
  when 'edifex' then 11024.400
  when 'dixon' then 16169.120
  when 'falcon' then 73496.000
  else max_amount
end,
updated_at = now()
where id in ('gns','build','follow','apex','edifex','dixon','falcon');

commit;