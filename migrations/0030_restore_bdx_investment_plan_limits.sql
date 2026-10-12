begin;

-- The BDX-native buy_investment_plan() RPC compares p_amount in BDX against
-- investment_plan_catalog.min_amount/max_amount. Migration 0025 stored the
-- USD equivalents of the published BDX limits, which made the effective
-- minimums too small after migration 0029 switched purchases to BDX.
-- Restore the published BDX denomination. This is a forward-only catalog
-- correction; it does not rewrite existing investments, transactions, or balances.
update public.investment_plan_catalog
set min_amount = case id
  when 'gns' then 4000
  when 'build' then 11000
  when 'follow' then 17000
  when 'apex' then 40000
  when 'edifex' then 90000
  when 'dixon' then 160000
  when 'falcon' then 220000
  else min_amount
end,
max_amount = case id
  when 'gns' then 10000
  when 'build' then 16000
  when 'follow' then 30000
  when 'apex' then 80000
  when 'edifex' then 150000
  when 'dixon' then 220000
  when 'falcon' then 1000000
  else max_amount
end,
updated_at = now()
where id in ('gns','build','follow','apex','edifex','dixon','falcon');

commit;
