-- Supabase/Postgres source schema for Global Beldex.
-- Authentication lives in Supabase Auth; user_id references auth.users(id).
create extension if not exists pgcrypto;

create table if not exists public.user_profile (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  username text unique, fullname text, phone text, country text, avatar_url text,
  kyc_status text not null default 'pending',
  kyc_verified_at timestamptz, two_factor_enabled boolean not null default false,
  total_deposits numeric(38,18) not null default 0,
  total_withdrawals numeric(38,18) not null default 0,
  available_balance numeric(38,18) not null default 0,
  locked_balance numeric(38,18) not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(user_id)
);

create table if not exists public.admin_user (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role text not null default 'admin',
  permissions text[] not null default array[]::text[],
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.transaction (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null, amount numeric(38,18) not null check (amount > 0),
  status text not null default 'pending',
  approval_status text not null default 'awaiting',
  method text, note text, approved_by uuid references public.admin_user(id) on delete set null,
  approval_reason text, approved_at timestamptz, settled_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.transaction_audit (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.transaction(id) on delete cascade,
  admin_id uuid references public.admin_user(id) on delete set null,
  action text not null, old_values jsonb, new_values jsonb, reason text,
  created_at timestamptz not null default now()
);

create index if not exists transaction_user_id_idx on public.transaction(user_id);
create index if not exists transaction_status_idx on public.transaction(status);
create index if not exists transaction_approval_status_idx on public.transaction(approval_status);
create index if not exists transaction_created_at_idx on public.transaction(created_at desc);
create index if not exists transaction_audit_transaction_id_idx on public.transaction_audit(transaction_id);
