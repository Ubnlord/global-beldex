-- Read-only available-balance roll-forward diagnostic.
-- Run only against a non-production snapshot or via an authorized read-only connection.
-- This script performs SELECTs only; it does not repair balances or modify audit records.
-- It intentionally emits ephemeral account labels, never user IDs or personal fields.
--
-- Sign convention is based on the existing transaction type contract:
-- deposit / bonus / referral = credit; withdraw / plan = debit.
-- If a new transaction type is introduced, it is surfaced as UNKNOWN and excluded
-- from the calculated net rather than silently assumed to be a credit or debit.
-- A zero current-vs-net delta is ledger-net alignment, NOT proof of a verified
-- opening balance. The system currently lacks a complete immutable opening snapshot
-- and complete balance-before/after audit trail for every balance mutation.

WITH profiles AS (
  SELECT
    p.user_id,
    p.created_at AS profile_created_at,
    p.available_balance::numeric AS usd_available_balance,
    p.bdx_balance::numeric AS bdx_available_balance,
    row_number() OVER (ORDER BY p.created_at, p.user_id) AS anon_account
  FROM public.user_profile p
),
tx_by_account AS (
  SELECT
    t.user_id,
    min(t.created_at) AS first_transaction_at,
    max(t.created_at) AS last_transaction_at,
    count(*) AS transaction_rows,
    count(*) FILTER (WHERE t.status = 'completed') AS completed_rows,
    count(*) FILTER (WHERE t.status <> 'completed') AS noncompleted_rows,
    count(*) FILTER (
      WHERE t.status = 'completed'
        AND t.type NOT IN ('deposit', 'bonus', 'referral', 'withdraw', 'plan')
    ) AS unknown_completed_type_rows,
    count(*) FILTER (
      WHERE t.status = 'completed'
        AND coalesce(t.currency, 'USD') NOT IN ('USD', 'BDX')
    ) AS unknown_completed_currency_rows,
    coalesce(sum(
      CASE
        WHEN t.status = 'completed'
         AND coalesce(t.currency, 'USD') = 'USD'
         AND t.type IN ('deposit', 'bonus', 'referral') THEN t.amount
        WHEN t.status = 'completed'
         AND coalesce(t.currency, 'USD') = 'USD'
         AND t.type IN ('withdraw', 'plan') THEN -t.amount
        ELSE 0
      END
    ), 0)::numeric AS usd_completed_ledger_net,
    coalesce(sum(
      CASE
        WHEN t.status = 'completed'
         AND t.currency = 'BDX'
         AND t.type IN ('deposit', 'bonus', 'referral') THEN t.amount
        WHEN t.status = 'completed'
         AND t.currency = 'BDX'
         AND t.type IN ('withdraw', 'plan') THEN -t.amount
        ELSE 0
      END
    ), 0)::numeric AS bdx_completed_ledger_net
  FROM public.transaction t
  GROUP BY t.user_id
),
balance_audit AS (
  SELECT
    a.user_id,
    count(*) FILTER (
      WHERE a.action IN ('fund_user', 'adjust_balance')
    ) AS admin_balance_audit_rows,
    count(*) FILTER (
      WHERE a.action IN ('fund_user', 'adjust_balance')
        AND a.old_values ? 'available_balance'
        AND a.new_values ? 'available_balance'
    ) AS admin_balance_audit_rows_with_before_after,
    max(a.created_at) FILTER (
      WHERE a.action IN ('fund_user', 'adjust_balance')
    ) AS last_admin_balance_audit_at
  FROM public.admin_action_audit a
  GROUP BY a.user_id
)
SELECT
  'acct-' || lpad(p.anon_account::text, 2, '0') AS anonymized_account,
  p.profile_created_at,
  tx.first_transaction_at,
  tx.last_transaction_at,
  coalesce(tx.transaction_rows, 0) AS transaction_rows,
  coalesce(tx.completed_rows, 0) AS completed_transaction_rows,
  coalesce(tx.noncompleted_rows, 0) AS noncompleted_transaction_rows,
  coalesce(tx.unknown_completed_type_rows, 0) AS unknown_completed_type_rows,
  coalesce(tx.unknown_completed_currency_rows, 0) AS unknown_completed_currency_rows,
  round(p.usd_available_balance, 6) AS current_usd_available,
  round(coalesce(tx.usd_completed_ledger_net, 0), 6) AS completed_usd_ledger_net,
  round(p.usd_available_balance - coalesce(tx.usd_completed_ledger_net, 0), 6)
    AS usd_current_minus_ledger_net,
  round(p.bdx_available_balance, 6) AS current_bdx_available,
  round(coalesce(tx.bdx_completed_ledger_net, 0), 6) AS completed_bdx_ledger_net,
  round(p.bdx_available_balance - coalesce(tx.bdx_completed_ledger_net, 0), 6)
    AS bdx_current_minus_ledger_net,
  coalesce(ba.admin_balance_audit_rows, 0) AS admin_balance_audit_rows,
  coalesce(ba.admin_balance_audit_rows_with_before_after, 0)
    AS admin_balance_audit_rows_with_before_after,
  ba.last_admin_balance_audit_at,
  CASE
    WHEN coalesce(tx.unknown_completed_type_rows, 0) > 0
      OR coalesce(tx.unknown_completed_currency_rows, 0) > 0
      THEN 'EXCEPTION: unknown completed transaction type/currency'
    WHEN coalesce(tx.noncompleted_rows, 0) > 0
      THEN 'REVIEW: non-completed transactions excluded from net'
    WHEN tx.first_transaction_at IS NULL
      THEN 'LIMITED: no transaction ledger; opening balance not evidenced'
    ELSE 'LEDGER-NET MATCH ONLY: opening balance and all direct mutations not proven'
  END AS rollforward_status
FROM profiles p
LEFT JOIN tx_by_account tx ON tx.user_id = p.user_id
LEFT JOIN balance_audit ba ON ba.user_id = p.user_id
ORDER BY p.anon_account;

-- Portfolio-level control: list transaction categories that the sign convention
-- did not recognize, and any non-completed entries that need separate disposition.
SELECT
  coalesce(t.currency, 'USD') AS currency,
  t.type,
  t.status,
  count(*) AS row_count,
  round(coalesce(sum(t.amount), 0)::numeric, 6) AS amount_total
FROM public.transaction t
WHERE t.status <> 'completed'
   OR t.type NOT IN ('deposit', 'bonus', 'referral', 'withdraw', 'plan')
   OR coalesce(t.currency, 'USD') NOT IN ('USD', 'BDX')
GROUP BY coalesce(t.currency, 'USD'), t.type, t.status
ORDER BY 1, 2, 3;

-- Deleted profiles/accounts cannot be reconstructed by this report. In particular,
-- do not interpret the account-label output as covering deleted/cascaded records.
