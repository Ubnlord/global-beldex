-- Admin users table
create table if not exists "admin_user" (
  "id" text not null primary key,
  "user_id" text not null references "user" ("id") on delete cascade,
  "role" text not null default 'admin', -- 'admin', 'moderator', 'support'
  "permissions" text[], -- array of permission strings
  "created_at" timestamptz default CURRENT_TIMESTAMP not null,
  "updated_at" timestamptz default CURRENT_TIMESTAMP not null,
  unique("user_id")
);

-- Enhanced transaction table with approval workflow
create table if not exists "transaction" (
  "id" text not null primary key,
  "user_id" text not null references "user" ("id") on delete cascade,
  "type" text not null, -- 'deposit', 'withdraw', 'swap', 'plan', 'referral', 'bonus'
  "amount" numeric not null,
  "status" text not null default 'pending', -- 'pending', 'approved', 'rejected', 'completed', 'failed'
  "approval_status" text not null default 'awaiting', -- 'awaiting', 'approved', 'rejected'
  "method" text, -- payment method
  "note" text, -- withdrawal address or additional info
  "approved_by" text references "admin_user" ("id") on delete set null,
  "approval_reason" text, -- reason for approval/rejection
  "approved_at" timestamptz,
  "settled_at" timestamptz,
  "created_at" timestamptz default CURRENT_TIMESTAMP not null,
  "updated_at" timestamptz default CURRENT_TIMESTAMP not null
);

-- User KYC/profile data
create table if not exists "user_profile" (
  "id" text not null primary key,
  "user_id" text not null references "user" ("id") on delete cascade,
  "username" text unique,
  "fullname" text,
  "phone" text,
  "country" text,
  "avatar_url" text,
  "kyc_status" text default 'pending', -- 'pending', 'verified', 'rejected'
  "kyc_verified_at" timestamptz,
  "two_factor_enabled" boolean default false,
  "total_deposits" numeric default 0,
  "total_withdrawals" numeric default 0,
  "available_balance" numeric default 0,
  "locked_balance" numeric default 0,
  "created_at" timestamptz default CURRENT_TIMESTAMP not null,
  "updated_at" timestamptz default CURRENT_TIMESTAMP not null,
  unique("user_id")
);

-- Transaction audit log
create table if not exists "transaction_audit" (
  "id" text not null primary key,
  "transaction_id" text not null references "transaction" ("id") on delete cascade,
  "admin_id" text references "admin_user" ("id") on delete set null,
  "action" text not null, -- 'created', 'approved', 'rejected', 'settled', 'cancelled'
  "old_values" jsonb,
  "new_values" jsonb,
  "reason" text,
  "created_at" timestamptz default CURRENT_TIMESTAMP not null
);

-- Indexes for better query performance
create index if not exists "transaction_user_id_idx" on "transaction" ("user_id");
create index if not exists "transaction_status_idx" on "transaction" ("status");
create index if not exists "transaction_approval_status_idx" on "transaction" ("approval_status");
create index if not exists "transaction_created_at_idx" on "transaction" ("created_at");
create index if not exists "admin_user_user_id_idx" on "admin_user" ("user_id");
create index if not exists "user_profile_user_id_idx" on "user_profile" ("user_id");
create index if not exists "transaction_audit_transaction_id_idx" on "transaction_audit" ("transaction_id");
create index if not exists "transaction_audit_admin_id_idx" on "transaction_audit" ("admin_id");
