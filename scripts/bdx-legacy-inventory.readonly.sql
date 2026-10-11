-- READ-ONLY inventory for BDX-native accounting rollout.
-- Run only on a controlled database snapshot first. This file contains SELECTs only.
-- Do not paste customer-level results into public issues/logs.
begin transaction read only;

-- 1. Wallet inventory by currency (separate rows/columns; never sum USD and BDX).
select
  count(*) as profile_count,
  coalesce(sum(available_balance), 0) as legacy_available_usd,
  coalesce(sum(locked_balance), 0) as legacy_locked_usd,
  coalesce(sum(bdx_balance), 0) as available_bdx,
  coalesce(sum(locked_bdx_balance), 0) as locked_bdx,
  count(*) filter (where available_balance < 0 or locked_balance < 0
    or bdx_balance < 0 or locked_bdx_balance < 0) as profiles_with_negative_balance
from public.user_profile;

-- 2. Investment principals and accrued profits by stored currency/status.
select
  coalesce(currency, 'USD') as currency,
  status,
  count(*) as investment_count,
  coalesce(sum(principal), 0) as principal_total,
  coalesce(sum(credited_profit), 0) as credited_profit_total,
  coalesce(sum(principal) filter (where status = 'active'), 0) as active_principal
from public.user_investment
group by coalesce(currency, 'USD'), status
order by 1, 2;

-- 3. Active investment principal vs wallet locks, separately by currency.
with active_principal as (
  select user_id, coalesce(currency, 'USD') as currency, sum(principal) as principal
  from public.user_investment
  where status = 'active'
  group by user_id, coalesce(currency, 'USD')
)
select
  p.user_id,
  'USD'::text as currency,
  p.locked_balance as wallet_locked,
  coalesce(a.principal, 0) as active_principal,
  p.locked_balance - coalesce(a.principal, 0) as lock_delta
from public.user_profile p
left join active_principal a on a.user_id = p.user_id and a.currency = 'USD'
where p.locked_balance <> coalesce(a.principal, 0)
union all
select
  p.user_id,
  'BDX'::text as currency,
  p.locked_bdx_balance as wallet_locked,
  coalesce(a.principal, 0) as active_principal,
  p.locked_bdx_balance - coalesce(a.principal, 0) as lock_delta
from public.user_profile p
left join active_principal a on a.user_id = p.user_id and a.currency = 'BDX'
where p.locked_bdx_balance <> coalesce(a.principal, 0)
order by user_id, currency;

-- 4. Transactions awaiting approval or approved but not settled, by currency.
select
  coalesce(currency, 'USD') as currency,
  type,
  status,
  approval_status,
  count(*) as request_count,
  coalesce(sum(amount), 0) as amount_total,
  min(created_at) as oldest_created_at,
  max(created_at) as newest_created_at
from public.transaction
where coalesce(status, '') in ('pending', 'awaiting')
   or coalesce(approval_status, '') in ('awaiting', 'approved')
  and coalesce(status, '') <> 'completed'
group by coalesce(currency, 'USD'), type, status, approval_status
order by 1, 2, 3, 4;

-- 5. Individual unresolved requests for case-by-case review.
select id, user_id, type, amount, coalesce(currency, 'USD') as currency,
       status, approval_status, request_id, created_at, approved_at, settled_at,
       method, note
from public.transaction
where (coalesce(status, '') in ('pending', 'awaiting')
    or coalesce(approval_status, '') in ('awaiting', 'approved'))
  and coalesce(status, '') <> 'completed'
order by created_at, id;

-- 6. Legacy USD profile totals vs completed USD transaction records.
with deposits as (
  select user_id, sum(amount) as amount
  from public.transaction
  where type = 'deposit' and status = 'completed'
    and coalesce(currency, 'USD') = 'USD'
  group by user_id
), withdrawals as (
  select user_id, sum(amount) as amount
  from public.transaction
  where type = 'withdraw' and status = 'completed'
    and coalesce(currency, 'USD') = 'USD'
  group by user_id
)
select p.user_id,
       p.total_deposits as profile_deposits_usd,
       coalesce(d.amount, 0) as ledger_deposits_usd,
       p.total_deposits - coalesce(d.amount, 0) as deposit_delta_usd,
       p.total_withdrawals as profile_withdrawals_usd,
       coalesce(w.amount, 0) as ledger_withdrawals_usd,
       p.total_withdrawals - coalesce(w.amount, 0) as withdrawal_delta_usd
from public.user_profile p
left join deposits d on d.user_id = p.user_id
left join withdrawals w on w.user_id = p.user_id
where p.total_deposits <> coalesce(d.amount, 0)
   or p.total_withdrawals <> coalesce(w.amount, 0)
order by p.user_id;

rollback;
