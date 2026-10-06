begin;

-- Legacy client-ledger data is no longer part of the application write path.
-- Remove all Data API access for ordinary clients rather than relying on its
-- legacy row policies.
revoke all on table public.books from anon, authenticated;

-- Admin action audit records are written by SECURITY DEFINER admin functions
-- and should never be directly mutable by browser clients. Keep authenticated
-- SELECT for the admin UI, protected by its RLS policy.
revoke insert, update, delete, truncate, references, trigger on table public.admin_action_audit from anon, authenticated;
grant select on table public.admin_action_audit to authenticated;

alter table public.admin_action_audit enable row level security;
drop policy if exists admin_action_audit_select on public.admin_action_audit;
create policy admin_action_audit_select
on public.admin_action_audit
for select to authenticated
using ((select public.is_admin()));

-- Defense-in-depth financial invariants. Existing production data was checked
-- before adding these constraints and contains no violating rows.
alter table public.user_profile
  add constraint user_profile_available_balance_nonnegative check (available_balance >= 0),
  add constraint user_profile_locked_balance_nonnegative check (locked_balance >= 0),
  add constraint user_profile_bdx_balance_nonnegative check (bdx_balance >= 0),
  add constraint user_profile_total_deposits_nonnegative check (total_deposits >= 0),
  add constraint user_profile_total_withdrawals_nonnegative check (total_withdrawals >= 0),
  add constraint user_profile_referral_earnings_nonnegative check (referral_earnings >= 0);

alter table public.transaction
  add constraint transaction_amount_positive check (amount > 0);

alter table public.user_investment
  add constraint user_investment_principal_positive check (principal > 0),
  add constraint user_investment_daily_rate_nonnegative check (daily_rate >= 0),
  add constraint user_investment_duration_positive check (duration_days > 0),
  add constraint user_investment_credited_profit_nonnegative check (credited_profit >= 0);

alter table public.investment_plan_catalog
  add constraint investment_plan_min_amount_positive check (min_amount > 0),
  add constraint investment_plan_max_amount_valid check (max_amount is null or max_amount >= min_amount),
  add constraint investment_plan_duration_positive check (duration_days > 0),
  add constraint investment_plan_daily_rate_nonnegative check (daily_rate >= 0);

commit;
