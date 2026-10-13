# BDX conversion: isolated validation and cutover gates

## Status

Planning and test contract only. This document does not authorize a production conversion, migration, deployment, or change to customer balances. Legacy USD records remain authoritative until a separately reviewed conversion is approved.

## Required conversion policy

- Capture one fresh BDX/USD quote from the same server-side market-price service used by the website at the approved cutover instant.
- Store the exact quote, quote source, provider timestamp when available, server-observed timestamp, and conversion-run identifier in a restricted audit record.
- Reject a missing, stale, non-positive, non-finite, out-of-policy, or unverifiable quote. Never use browser localStorage, a remembered quote, or an emergency fallback for accounting conversion.
- Calculate BDX units using USD amount / approved USD-per-BDX price, with an explicitly documented decimal scale and rounding policy. Record any rounding remainder; never silently discard value.
- Make the operation atomic and idempotent. A second attempt for the same conversion run/account must not credit again. Lock affected account and ledger rows during the transaction.
- Preserve original USD amounts and identifiers in an immutable/restricted mapping before changing any canonical display or balance field. Preserve historical transaction amounts/currency as historical facts; do not rewrite them as if the original transaction occurred in BDX.
- Do not combine USD and BDX values in accounting totals. Keep a traceable link between each original record, conversion record, resulting BDX amount, rate and audit event.
- Existing investments, locked principal, accrued/credited profit, pending or unresolved deposits/withdrawals, referrals, and transaction history must each have an explicit disposition. No automatic conversion of unresolved or disputed records.

## Isolated test matrix

1. Fresh valid quote: expected BDX = USD / captured quote; exact quote metadata is persisted.
2. Provider unavailable, timeout, malformed response, zero/negative price, stale timestamp, or invalid range: conversion aborts with no account or ledger writes.
3. Cached/localStorage/emergency fallback only: conversion aborts.
4. Two accounts with available and locked USD: per-account totals reconcile independently; no currency mixing.
5. Active investments and profit: principal, locked amount, accrued profit, and credited profit reconcile without double-credit.
6. Historical transactions: original amount and currency remain preserved; mapping references the original transaction IDs.
7. Pending, rejected, reversed, or disputed transactions: no silent conversion; require an explicit reviewed disposition.
8. Retry/concurrent invocation: exactly one conversion effect per account and run; duplicate attempt is a no-op or a clear rejection.
9. Forced error halfway through: full rollback, with no partial balance or audit state.
10. Rounding boundaries and tiny amounts: deterministic scale; remainder is reported and reconciled.
11. Reversal/rollback rehearsal: restore original state from protected mapping in an isolated fixture and prove before/after checksums and totals.
12. Post-conversion price movement: BDX unit balances remain fixed; USD-equivalent display recalculates from the current validated live quote and does not mutate accounting units.
13. Authorization: ordinary users cannot invoke conversion or read other users' audit mappings; only narrowly authorized server-side operation can run it.
14. Reconciliation: per-account and aggregate USD source totals, BDX destination totals, locked investment principal, profits, referrals and transaction counts match expected dispositions with zero unexplained deltas.

## Required evidence before rollout

- Fresh isolated database built from the exact candidate commit and production-compatible schema fixture.
- Passing migration tests, pgTAP assertions, security regression tests, typecheck/lint/build and secret scan on the same commit.
- Synthetic-accounting report showing all per-account and aggregate deltas, conversion remainders, excluded exceptions, and duplicate-run behavior.
- Read-only production inventory and independently reviewed customer-level reconciliation. Do not export unnecessary personal data.
- Explicit approval of the conversion valuation policy, rounding policy, exception handling, rollback plan, maintenance window, and exact live quote source.
- Separate explicit release approval. A passing isolated CI run is not production authorization.

## Live valuation behavior after conversion

The recorded conversion quote is a one-time historical accounting input. After conversion, BDX unit quantities stay fixed. Their displayed USD equivalent changes as the website's validated live BDX/USD price changes. A future market-price change must never retroactively rewrite the captured conversion rate or alter BDX units.
