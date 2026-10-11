# BDX-native accounting: legacy reconciliation runbook

## Status and scope

This runbook applies to the BDX-native accounting rollout in PR #44. It is a policy and operational checklist, not authorization to convert data. The inventory SQL in `scripts/bdx-legacy-inventory.readonly.sql` is read-only and must be run against a controlled database snapshot first.

**Default policy: preserve historical USD records as USD.** Do not infer a record's denomination from a UI label, plan name, payment method, or a missing currency field. For historical transactions/investments, a missing currency is treated as USD only where existing schema/migration semantics explicitly define that legacy default.

No production migration or conversion is authorized by this document.

## Denomination policy

| Record | Default treatment | Conversion rule |
|---|---|---|
| `available_balance`, `locked_balance` | Preserve as legacy USD values; show under a clearly labelled legacy USD section. | No automatic conversion. Convert only after a reviewed account-level reconciliation and explicit approval. |
| `bdx_balance`, `locked_bdx_balance` | Canonical BDX wallet values. | Never add USD values to these fields without a conversion journal and reviewed source/destination totals. |
| `user_investment.principal`, `credited_profit` | Respect the row's stored `currency`; legacy missing currency is USD under the migration default. Preserve original principal, accrued profit, dates, rate, status and history. | Do not rewrite existing investment rows in place. If conversion is approved, create a linked, auditable adjustment/migration record and verify principal, accrued profit, maturity and lock-release treatment. |
| `transaction.amount` | Respect `currency`; historical missing currency is USD only under the schema default. | Never settle a legacy USD request through a BDX-only settlement path. Reconcile it using a separate, explicitly authorized workflow. |
| Pending/approved-but-unsettled deposits and withdrawals | Preserve status and denomination; inventory separately. | Do not auto-settle, auto-reject or create a replacement request during conversion. Resolve each original request exactly once. |
| Referral earnings, interest/profit, deposits/withdrawal totals | Compare and report separately by currency. | Never sum or compare unlike currencies without an explicitly recorded quote and conversion record. |

The fixed rate used for new requests is not approval to convert historical assets. A historical conversion rate must be explicitly approved for the relevant cohort/date and recorded per conversion. If no approved historical valuation policy exists, retain the record in its original currency and require manual review.

## Required reconciliation controls

1. **Snapshot and inventory:** run the read-only SQL on an isolated database snapshot; retain the timestamp, migration/head commit, row counts and output securely.
2. **Per-user source totals:** report USD available/locked balances, active USD/BDX principal, accrued profit by currency, and pending/approved-but-unsettled transactions by currency.
3. **Exception report:** investigate negative balances, missing/unsupported currencies, lock totals that differ from active principal, completed transaction totals that differ from profile totals, and pending withdrawals with an unexpected reservation.
4. **Approval:** document the conversion policy, quote/rate source, rounding/precision rules, eligible records, exclusions, and accounting sign-off before building a write path.
5. **Idempotency:** every approved reconciliation batch and item must have a stable unique idempotency key. A retry with the same key and same parameters returns the prior result without another credit; reuse with different parameters must fail. Enforce this in the database with a unique constraint, not just UI logic.
6. **Atomicity:** source debit/closure, destination credit, linked ledger rows, reconciliation item status and audit record must commit in one database transaction. A failed step must roll back all of them.
7. **Audit:** store source record IDs, source amount/currency, destination amount/currency, approved rate and its provenance, rounding, before/after values, operator/admin ID, reason, batch ID, idempotency key and timestamps. Do not overwrite historical transaction or investment facts.
8. **Re-run and compare:** after reconciliation, rerun inventory and compare source and destination totals by currency and user. Require zero unexplained deltas before rollout.

## Mandatory isolated test matrix

- A normal eligible USD balance converts once to the approved BDX amount; the source USD amount is reduced/closed exactly once and the destination BDX credit is recorded exactly once.
- Retrying the same batch/item and same idempotency key does not duplicate any credit or audit settlement.
- Reusing a key with different user/amount/currency/rate fails without changing balances.
- A rejected or ineligible legacy transaction is not settled or credited; its original state and denomination remain visible.
- Pending and approved-but-unsettled withdrawals are handled by explicit policy; reservations are neither lost nor released twice.
- Active, matured and already-completed investments preserve principal/profit history; principal return and lock release cannot happen twice.
- Injected failures after source debit, before destination credit, and before audit persistence roll back atomically.
- Concurrent retries for the same item result in one conversion.
- Admin without the specific permission, ordinary user, and blocked user cannot invoke the reconciliation path.
- Every successful and rejected reconciliation attempt has the expected audit trail; no production credentials or live records are used.

## Admin console acceptance criteria

- Show `Available (legacy USD)`, `Locked (legacy USD)`, `Available (BDX)`, and `Locked (BDX)` as separate values.
- Show currency on every transaction and investment amount using the stored row currency; missing/unsupported currency is visibly marked for review, not silently labelled BDX.
- Show investment principal and accrued profit in the investment's stored currency.
- Label BDX adjustment and legacy USD adjustment as separate actions backed by separate, permission-checked database functions. Do not reuse a BDX-only adjustment RPC for a USD-labelled control.
- Keep legacy USD pending requests in a review queue; disable normal BDX settlement for them and link to the documented reconciliation workflow.
- Require a reason for every adjustment/reconciliation and show a confirmation with source and destination denominations.
- Test UI rendering and action permissions against seeded USD and BDX records in isolation.

## Release gate

Do not merge or deploy the accounting change until the admin compatibility work, isolated reconciliation test matrix, final diff review and all required CI checks pass on the same final commit. The Supabase preview check being skipped is not a substitute for isolated database tests. Production migration and any real-data reconciliation require a separate explicit approval and execution plan.
