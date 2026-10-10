begin;

-- Add investment-level traceability for newly generated investment transactions.
-- Existing rows remain NULL because their original investment cannot be inferred
-- safely from amount and timestamp alone.
alter table public.transaction
  add column if not exists investment_id uuid
  references public.user_investment(id) on delete restrict;

create index if not exists transaction_investment_id_created_at_idx
  on public.transaction (investment_id, created_at desc)
  where investment_id is not null;

comment on column public.transaction.investment_id is
  'Investment that generated this transaction; NULL for legacy or non-investment transactions where attribution is unavailable.';

commit;
