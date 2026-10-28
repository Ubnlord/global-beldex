begin;

-- Audit ledger for real Bitcoin withdrawal attempts. This table does not
-- broadcast transactions and does not settle the application withdrawal.
-- A trusted payout service must create/update rows only after validating the
-- approved withdrawal, destination, BTC amount, and idempotency key.
create table if not exists public.bitcoin_withdrawal_payout (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null unique
    references public.transaction(id) on delete restrict,
  idempotency_key uuid not null unique,
  destination_address text not null
    check (length(destination_address) between 14 and 128),
  amount_sats bigint not null check (amount_sats > 0),
  fee_sats bigint check (fee_sats is null or fee_sats >= 0),
  status text not null default 'queued'
    check (status in ('queued','broadcast','confirming','confirmed','failed','manual_review')),
  txid text unique
    check (txid is null or txid ~ '^[0-9a-fA-F]{64}$'),
  confirmations integer not null default 0 check (confirmations >= 0),
  block_height bigint check (block_height is null or block_height >= 0),
  block_hash text,
  provider text,
  provider_reference text,
  failure_code text,
  failure_detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  broadcast_at timestamptz,
  confirmed_at timestamptz,
  constraint bitcoin_payout_confirmed_requires_txid
    check (status not in ('broadcast','confirming','confirmed') or txid is not null),
  constraint bitcoin_payout_confirmed_requires_block
    check (status <> 'confirmed' or (confirmations > 0 and block_height is not null and block_hash is not null and confirmed_at is not null))
);

create index if not exists bitcoin_withdrawal_payout_status_idx
  on public.bitcoin_withdrawal_payout(status, created_at);

alter table public.bitcoin_withdrawal_payout enable row level security;
revoke all on public.bitcoin_withdrawal_payout from public, anon, authenticated, service_role;
grant select, insert, update on public.bitcoin_withdrawal_payout to service_role;

comment on table public.bitcoin_withdrawal_payout is
  'Server-only Bitcoin payout attempt ledger. Not a broadcaster and not proof of payment by itself; generic admin settlement remains blocked until an audited payout workflow verifies chain state.';

commit;
