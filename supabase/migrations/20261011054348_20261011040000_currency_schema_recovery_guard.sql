begin;

-- Recovery guard for deployments where the currency-aware migrations were
-- already merged but the production schema is still behind. This migration is
-- deliberately additive: it does not update balances, investments, ledger rows,
-- accrual timestamps, or historical-interest transactions.
--
-- Existing rows receive the legacy denomination USD when a column is first
-- introduced. This is a denomination default, not a conversion of amounts.

alter table public.user_profile
  add column if not exists locked_bdx_balance numeric(38,18) not null default 0,
  add column if not exists total_deposits_bdx numeric(38,18) not null default 0,
  add column if not exists total_withdrawals_bdx numeric(38,18) not null default 0;

alter table public.user_investment
  add column if not exists currency text not null default 'USD';

alter table public.transaction
  add column if not exists currency text not null default 'USD';

-- Refuse invalid denomination values rather than silently rewriting financial
-- records. The canonical migrations also install currency constraints; these
-- named constraints protect deployments where the guard runs independently.
do $currency_constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_investment'::regclass
      and conname = 'user_investment_currency_usd_bdx_guard'
  ) then
    alter table public.user_investment
      add constraint user_investment_currency_usd_bdx_guard
      check (currency in ('USD', 'BDX')) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.transaction'::regclass
      and conname = 'transaction_currency_usd_bdx_guard'
  ) then
    alter table public.transaction
      add constraint transaction_currency_usd_bdx_guard
      check (currency in ('USD', 'BDX')) not valid;
  end if;
end;
$currency_constraints$;

alter table public.user_investment
  validate constraint user_investment_currency_usd_bdx_guard;
alter table public.transaction
  validate constraint transaction_currency_usd_bdx_guard;

comment on column public.user_investment.currency is
  'Investment denomination. Legacy rows default to USD; USD and BDX amounts are never combined.';
comment on column public.transaction.currency is
  'Transaction denomination. Legacy rows default to USD; USD and BDX amounts are never combined.';
comment on column public.user_profile.locked_bdx_balance is
  'BDX principal reserved in active BDX investments; separate from USD locked_balance.';
comment on column public.user_profile.total_deposits_bdx is
  'Completed BDX deposits total; separate from USD total_deposits.';
comment on column public.user_profile.total_withdrawals_bdx is
  'Completed BDX withdrawals total; separate from USD total_withdrawals.';

commit;
