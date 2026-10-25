begin;

-- Isolated Bitcoin deposit tracking. This migration deliberately does not
-- modify balances or the existing financial transaction RPC.
create table if not exists public.bitcoin_deposit_intent (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  receiving_address text not null
    check (receiving_address = 'bc1qzlq3r8e39pwl8mv3vthdxr7nnxlrq92gvs3p0m'),
  target_bdx numeric(30, 8) not null check (target_bdx >= 4000),
  quoted_btc numeric(20, 8) not null check (quoted_btc > 0),
  quote_rate_bdx_per_btc numeric(30, 8) not null check (quote_rate_bdx_per_btc > 0),
  quote_expires_at timestamptz not null,
  status text not null default 'awaiting_payment'
    check (status in ('awaiting_payment','detected','confirming','verified','credited','expired','underpaid','review')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bitcoin_deposit_intent_user_created_idx
  on public.bitcoin_deposit_intent(user_id, created_at desc);
create index if not exists bitcoin_deposit_intent_status_idx
  on public.bitcoin_deposit_intent(status, created_at);

-- A transaction hash can only be attached once, preventing cross-intent reuse.
create table if not exists public.bitcoin_chain_observation (
  txid text primary key check (txid ~ '^[0-9a-fA-F]{64}$'),
  intent_id uuid not null references public.bitcoin_deposit_intent(id) on delete restrict,
  output_index integer not null check (output_index >= 0),
  destination_address text not null,
  received_sats bigint not null check (received_sats > 0),
  confirmations integer not null default 0 check (confirmations >= 0),
  block_height bigint,
  block_hash text,
  verification_provider text not null,
  provider_payload_hash text not null,
  observed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (txid, output_index)
);

create index if not exists bitcoin_chain_observation_intent_idx
  on public.bitcoin_chain_observation(intent_id);

alter table public.bitcoin_deposit_intent enable row level security;
alter table public.bitcoin_chain_observation enable row level security;

-- Users may view only their own deposit intents. All inserts and updates must
-- come through trusted server-side functions using service-role credentials.
drop policy if exists bitcoin_deposit_intent_select_own on public.bitcoin_deposit_intent;
create policy bitcoin_deposit_intent_select_own
  on public.bitcoin_deposit_intent for select to authenticated
  using (auth.uid() = user_id);

revoke all on public.bitcoin_deposit_intent from anon, authenticated;
grant select on public.bitcoin_deposit_intent to authenticated;
revoke all on public.bitcoin_chain_observation from anon, authenticated;

comment on table public.bitcoin_deposit_intent is
  'BTC deposit intent tracking only. Does not credit BDX; requires independent chain verification and a separate audited credit operation.';
comment on table public.bitcoin_chain_observation is
  'Server-observed Bitcoin chain outputs. Unique txid and output prevent duplicate attachment. No client access and no balance mutation.';

commit;
