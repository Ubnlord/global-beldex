


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."accrue_user_investments"("p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_inv public.user_investment;
  v_now timestamptz := now();
  v_elapsed_days integer;
  v_previous_days integer;
  v_days integer;
  v_profit numeric;
  v_principal_return numeric;
  v_total numeric := 0;
  v_done boolean;
  v_admin boolean := public.is_admin();
  v_scheduled boolean := auth.uid() is null;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if v_uid <> auth.uid() then
    if not v_scheduled and (not v_admin or not public.admin_has_permission('manage_users')) then
      raise exception 'Permission denied';
    end if;
  end if;
  perform public.assert_user_can_transact(v_uid);

  for v_inv in
    select * from public.user_investment
    where user_id = v_uid and status = 'active' and daily_accrual_enabled = true
    order by created_at
    for update
  loop
    v_elapsed_days := least(v_inv.duration_days,
      greatest(0, floor(extract(epoch from (v_now - v_inv.started_at))/86400)::integer));
    v_previous_days := least(v_inv.duration_days,
      greatest(0, floor(extract(epoch from (v_inv.last_accrual_at - v_inv.started_at))/86400)::integer));
    v_days := greatest(0, v_elapsed_days - v_previous_days);

    if v_days > 0 then
      v_profit := v_inv.principal * v_inv.daily_rate * v_days;
      v_done := v_elapsed_days >= v_inv.duration_days;
      v_principal_return := case when v_done then v_inv.principal else 0 end;
      -- Preserve the legacy numeric return value as USD-only; BDX profit is
      -- credited and ledgered in BDX but must not be summed with USD.
      if coalesce(v_inv.currency,'USD') = 'USD' then
        v_total := v_total + v_profit;
      end if;

      if v_inv.currency = 'BDX' then
        update public.user_profile
        set bdx_balance = bdx_balance + v_profit + v_principal_return,
            locked_bdx_balance = case when v_done then greatest(0,locked_bdx_balance-v_inv.principal) else locked_bdx_balance end,
            updated_at = now()
        where user_id = v_uid;
      else
        update public.user_profile
        set available_balance = available_balance + v_profit + v_principal_return,
            locked_balance = case when v_done then greatest(0,locked_balance-v_inv.principal) else locked_balance end,
            updated_at = now()
        where user_id = v_uid;
      end if;

      update public.user_investment
      set credited_profit = credited_profit + v_profit,
          last_accrual_at = least(v_inv.started_at + make_interval(days => v_inv.duration_days), v_now),
          status = case when v_done then 'completed' else 'active' end,
          completed_at = case when v_done then v_now else completed_at end,
          updated_at = now()
      where id = v_inv.id;

      insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
      values(v_uid,'bonus',v_profit,v_inv.currency,'completed','approved',
        case when v_done then 'Plan maturity' else 'Daily interest' end,
        'Server-side investment profit');

      if v_done then
        insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
        values(v_uid,'bonus',v_inv.principal,v_inv.currency,'completed','approved',
          'Plan maturity','Investment principal returned');
      end if;
    end if;
  end loop;
  return v_total;
end;
$$;


ALTER FUNCTION "public"."accrue_user_investments"("p_user_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."user_profile" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "username" "text",
    "fullname" "text",
    "phone" "text",
    "country" "text",
    "avatar_url" "text",
    "kyc_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "kyc_verified_at" timestamp with time zone,
    "two_factor_enabled" boolean DEFAULT false NOT NULL,
    "total_deposits" numeric(38,18) DEFAULT 0 NOT NULL,
    "total_withdrawals" numeric(38,18) DEFAULT 0 NOT NULL,
    "available_balance" numeric(38,18) DEFAULT 0 NOT NULL,
    "locked_balance" numeric(38,18) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "bdx_balance" numeric(38,18) DEFAULT 0 NOT NULL,
    "referral_code" "text",
    "referred_by_user_id" "uuid",
    "referral_earnings" numeric(38,18) DEFAULT 0 NOT NULL,
    "blocked" boolean DEFAULT false NOT NULL,
    "blocked_reason" "text",
    "blocked_at" timestamp with time zone,
    "locked_bdx_balance" numeric(38,18) DEFAULT 0 NOT NULL,
    "total_deposits_bdx" numeric(38,18) DEFAULT 0 NOT NULL,
    "total_withdrawals_bdx" numeric(38,18) DEFAULT 0 NOT NULL,
    "referral_earnings_bdx" numeric(38,18) DEFAULT 0 NOT NULL,
    CONSTRAINT "user_profile_available_balance_check" CHECK (("available_balance" >= (0)::numeric)),
    CONSTRAINT "user_profile_available_balance_nonnegative" CHECK (("available_balance" >= (0)::numeric)),
    CONSTRAINT "user_profile_bdx_balance_nonnegative" CHECK (("bdx_balance" >= (0)::numeric)),
    CONSTRAINT "user_profile_kyc_status_check" CHECK (("kyc_status" = ANY (ARRAY['pending'::"text", 'verified'::"text", 'rejected'::"text"]))),
    CONSTRAINT "user_profile_locked_balance_check" CHECK (("locked_balance" >= (0)::numeric)),
    CONSTRAINT "user_profile_locked_balance_nonnegative" CHECK (("locked_balance" >= (0)::numeric)),
    CONSTRAINT "user_profile_referral_earnings_nonnegative" CHECK (("referral_earnings" >= (0)::numeric)),
    CONSTRAINT "user_profile_total_deposits_check" CHECK (("total_deposits" >= (0)::numeric)),
    CONSTRAINT "user_profile_total_deposits_nonnegative" CHECK (("total_deposits" >= (0)::numeric)),
    CONSTRAINT "user_profile_total_withdrawals_check" CHECK (("total_withdrawals" >= (0)::numeric)),
    CONSTRAINT "user_profile_total_withdrawals_nonnegative" CHECK (("total_withdrawals" >= (0)::numeric))
);


ALTER TABLE "public"."user_profile" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_profile"."total_deposits" IS 'Legacy USD-denominated completed deposits total; never combine with BDX.';



COMMENT ON COLUMN "public"."user_profile"."total_withdrawals" IS 'Legacy USD-denominated completed withdrawals total; never combine with BDX.';



COMMENT ON COLUMN "public"."user_profile"."locked_bdx_balance" IS 'BDX principal reserved in active BDX investments; separate from USD locked_balance.';



COMMENT ON COLUMN "public"."user_profile"."total_deposits_bdx" IS 'Completed BDX deposits total; separate from USD total_deposits.';



COMMENT ON COLUMN "public"."user_profile"."total_withdrawals_bdx" IS 'Completed BDX withdrawals total; separate from USD total_withdrawals.';



COMMENT ON COLUMN "public"."user_profile"."referral_earnings_bdx" IS 'Completed BDX referral commissions, separate from USD referral earnings.';



CREATE OR REPLACE FUNCTION "public"."admin_adjust_balance"("p_user_id" "uuid", "p_delta" numeric, "p_reason" "text") RETURNS "public"."user_profile"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_profile public.user_profile;
  v_admin_id uuid;
  v_before numeric;
  v_type text;
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
begin
  select id into v_admin_id
  from public.admin_user
  where user_id = auth.uid();

  if v_admin_id is null or not public.admin_has_permission('approve_transactions') then
    raise exception 'not authorized';
  end if;

  if p_user_id is null or p_delta is null or p_delta = 0 then
    raise exception 'invalid balance adjustment';
  end if;

  if v_reason is null then
    raise exception 'reason is required';
  end if;

  select * into v_profile
  from public.user_profile
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'user profile not found';
  end if;

  if v_profile.blocked then
    raise exception 'blocked user cannot have balance adjusted';
  end if;

  if p_delta < 0 and v_profile.available_balance + p_delta < 0 then
    raise exception 'insufficient available balance';
  end if;

  v_before := v_profile.available_balance;
  v_type := case when p_delta > 0 then 'bonus' else 'withdraw' end;

  update public.user_profile
  set available_balance = available_balance + p_delta,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_profile;

  insert into public.transaction
    (user_id,type,amount,status,method,note,approved_by,approval_status,approval_reason,approved_at,settled_at,created_at)
  values
    (p_user_id,v_type,abs(p_delta),'completed','admin',v_reason,v_admin_id,'approved',v_reason,now(),now(),now());

  insert into public.admin_action_audit
    (admin_id,user_id,action,target_id,old_values,new_values,reason,created_at)
  values
    (v_admin_id,p_user_id,'adjust_balance',p_user_id,
     jsonb_build_object('available_balance',v_before),
     jsonb_build_object('available_balance',v_profile.available_balance),
     v_reason,now());

  return v_profile;
end;
$$;


ALTER FUNCTION "public"."admin_adjust_balance"("p_user_id" "uuid", "p_delta" numeric, "p_reason" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transaction" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "amount" numeric(38,18) NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "approval_status" "text" DEFAULT 'awaiting'::"text" NOT NULL,
    "method" "text",
    "note" "text",
    "approved_by" "uuid",
    "approval_reason" "text",
    "approved_at" timestamp with time zone,
    "settled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "request_id" "uuid",
    "currency" "text" DEFAULT 'USD'::"text" NOT NULL,
    CONSTRAINT "transaction_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "transaction_amount_positive" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "transaction_approval_status_check" CHECK (("approval_status" = ANY (ARRAY['awaiting'::"text", 'approved'::"text", 'rejected'::"text"]))),
    CONSTRAINT "transaction_currency_check" CHECK (("currency" = ANY (ARRAY['USD'::"text", 'BDX'::"text"]))),
    CONSTRAINT "transaction_currency_usd_bdx_guard" CHECK (("currency" = ANY (ARRAY['USD'::"text", 'BDX'::"text"]))),
    CONSTRAINT "transaction_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'completed'::"text", 'failed'::"text"]))),
    CONSTRAINT "transaction_type_check" CHECK (("type" = ANY (ARRAY['deposit'::"text", 'withdraw'::"text", 'swap'::"text", 'plan'::"text", 'referral'::"text", 'bonus'::"text"])))
);


ALTER TABLE "public"."transaction" OWNER TO "postgres";


COMMENT ON COLUMN "public"."transaction"."currency" IS 'Transaction denomination. Legacy rows default to USD; USD and BDX amounts are never combined.';



CREATE OR REPLACE FUNCTION "public"."admin_approve_deposit"("p_transaction_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_tx public.transaction;
begin
  if not public.admin_has_permission('approve_transactions') then raise exception 'not authorized'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id;
  if not found or v_tx.type <> 'deposit' then raise exception 'deposit transaction not found'; end if;
  return public.admin_approve_transaction(p_transaction_id,p_reason);
end;
$$;


ALTER FUNCTION "public"."admin_approve_deposit"("p_transaction_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_approve_transaction"("p_transaction_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_admin public.admin_user; v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.approval_status<>'awaiting' then raise exception 'Transaction is not awaiting approval'; end if;

  update public.transaction
  set approval_status='approved',
      status=case when type in ('deposit','withdraw') then 'pending' else 'approved' end,
      approved_by=v_admin.id,approval_reason=p_reason,approved_at=now(),updated_at=now()
  where id=p_transaction_id
  returning * into v_tx;

  insert into public.transaction_audit(
    transaction_id,admin_id,action,old_values,new_values,reason
  )
  values(
    v_tx.id,v_admin.id,'approved',
    jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status',v_tx.approval_status,'status',v_tx.status),
    p_reason
  );

  return v_tx;
end;
$$;


ALTER FUNCTION "public"."admin_approve_transaction"("p_transaction_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_approve_withdrawal"("p_transaction_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_tx public.transaction;
begin
  if not public.admin_has_permission('approve_transactions') then raise exception 'not authorized'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id;
  if not found or v_tx.type <> 'withdraw' then raise exception 'withdrawal transaction not found'; end if;
  return public.admin_approve_transaction(p_transaction_id,p_reason);
end;
$$;


ALTER FUNCTION "public"."admin_approve_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_financial_reconciliation"() RETURNS TABLE("user_id" "uuid", "available_balance" numeric, "locked_balance" numeric, "expected_locked_balance" numeric, "locked_delta" numeric, "total_deposits" numeric, "recorded_deposits" numeric, "deposits_delta" numeric, "total_withdrawals" numeric, "recorded_withdrawals" numeric, "withdrawals_delta" numeric, "referral_earnings" numeric, "recorded_referrals" numeric, "referral_delta" numeric, "credited_investment_profit" numeric, "recorded_investment_profit" numeric, "investment_profit_delta" numeric, "negative_balance" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_admin() then raise exception 'Permission denied'; end if;
  return query
  with d as (select t.user_id,sum(t.amount) amount from public.transaction t where t.type='deposit' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id),
  w as (select t.user_id,sum(t.amount) amount from public.transaction t where t.type='withdraw' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id),
  r as (select t.user_id,sum(t.amount) amount from public.transaction t where t.type='referral' and t.status='completed' group by t.user_id),
  ip as (select t.user_id,sum(t.amount) amount from public.transaction t where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit' and coalesce(t.currency,'USD')='USD' group by t.user_id),
  inv as (select ui.user_id,
    coalesce(sum(ui.principal) filter(where ui.status='active' and coalesce(ui.currency,'USD')='USD'),0) active_principal,
    coalesce(sum(ui.credited_profit) filter(where coalesce(ui.currency,'USD')='USD'),0) profit
    from public.user_investment ui group by ui.user_id)
  select p.user_id,p.available_balance,p.locked_balance,coalesce(inv.active_principal,0),
    p.locked_balance-coalesce(inv.active_principal,0),p.total_deposits,coalesce(d.amount,0),p.total_deposits-coalesce(d.amount,0),
    p.total_withdrawals,coalesce(w.amount,0),p.total_withdrawals-coalesce(w.amount,0),
    p.referral_earnings,coalesce(r.amount,0),p.referral_earnings-coalesce(r.amount,0),
    coalesce(inv.profit,0),coalesce(ip.amount,0),coalesce(inv.profit,0)-coalesce(ip.amount,0),
    p.available_balance<0 or p.locked_balance<0 or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p left join d on d.user_id=p.user_id left join w on w.user_id=p.user_id
  left join r on r.user_id=p.user_id left join ip on ip.user_id=p.user_id left join inv on inv.user_id=p.user_id
  order by p.created_at;
end;
$$;


ALTER FUNCTION "public"."admin_financial_reconciliation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_financial_reconciliation_v2"() RETURNS TABLE("user_id" "uuid", "available_balance" numeric, "locked_balance" numeric, "expected_locked_balance" numeric, "locked_delta" numeric, "total_deposits" numeric, "recorded_deposits" numeric, "deposits_delta" numeric, "total_withdrawals" numeric, "recorded_withdrawals" numeric, "withdrawals_delta" numeric, "referral_earnings" numeric, "recorded_referrals" numeric, "referral_delta" numeric, "credited_investment_profit" numeric, "recorded_investment_profit" numeric, "investment_profit_delta" numeric, "bdx_balance" numeric, "locked_bdx_balance" numeric, "expected_locked_bdx_balance" numeric, "locked_bdx_delta" numeric, "total_deposits_bdx" numeric, "recorded_deposits_bdx" numeric, "deposits_bdx_delta" numeric, "total_withdrawals_bdx" numeric, "recorded_withdrawals_bdx" numeric, "withdrawals_bdx_delta" numeric, "credited_investment_profit_bdx" numeric, "recorded_investment_profit_bdx" numeric, "investment_profit_bdx_delta" numeric, "negative_balance" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_admin() then raise exception 'Permission denied'; end if;
  return query
  with d_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), w_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), d_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and t.currency='BDX' group by t.user_id
  ), w_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and t.currency='BDX' group by t.user_id
  ), r as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='referral' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), ip_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit'
      and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), ip_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit'
      and t.currency='BDX' group by t.user_id
  ), inv as (
    select ui.user_id,
      coalesce(sum(ui.principal) filter(where ui.status='active' and coalesce(ui.currency,'USD')='USD'),0) active_usd,
      coalesce(sum(ui.credited_profit) filter(where coalesce(ui.currency,'USD')='USD'),0) profit_usd,
      coalesce(sum(ui.principal) filter(where ui.status='active' and ui.currency='BDX'),0) active_bdx,
      coalesce(sum(ui.credited_profit) filter(where ui.currency='BDX'),0) profit_bdx
    from public.user_investment ui group by ui.user_id
  )
  select p.user_id,p.available_balance,p.locked_balance,
    coalesce(inv.active_usd,0),p.locked_balance-coalesce(inv.active_usd,0),
    p.total_deposits,coalesce(d_usd.amount,0),p.total_deposits-coalesce(d_usd.amount,0),
    p.total_withdrawals,coalesce(w_usd.amount,0),p.total_withdrawals-coalesce(w_usd.amount,0),
    p.referral_earnings,coalesce(r.amount,0),p.referral_earnings-coalesce(r.amount,0),
    coalesce(inv.profit_usd,0),coalesce(ip_usd.amount,0),coalesce(inv.profit_usd,0)-coalesce(ip_usd.amount,0),
    p.bdx_balance,p.locked_bdx_balance,coalesce(inv.active_bdx,0),p.locked_bdx_balance-coalesce(inv.active_bdx,0),
    p.total_deposits_bdx,coalesce(d_bdx.amount,0),p.total_deposits_bdx-coalesce(d_bdx.amount,0),
    p.total_withdrawals_bdx,coalesce(w_bdx.amount,0),p.total_withdrawals_bdx-coalesce(w_bdx.amount,0),
    coalesce(inv.profit_bdx,0),coalesce(ip_bdx.amount,0),coalesce(inv.profit_bdx,0)-coalesce(ip_bdx.amount,0),
    p.available_balance<0 or p.locked_balance<0 or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p
  left join d_usd on d_usd.user_id=p.user_id left join w_usd on w_usd.user_id=p.user_id
  left join d_bdx on d_bdx.user_id=p.user_id left join w_bdx on w_bdx.user_id=p.user_id
  left join r on r.user_id=p.user_id left join ip_usd on ip_usd.user_id=p.user_id
  left join ip_bdx on ip_bdx.user_id=p.user_id left join inv on inv.user_id=p.user_id
  order by p.created_at;
end;
$$;


ALTER FUNCTION "public"."admin_financial_reconciliation_v2"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_fund_user"("p_user_id" "uuid", "p_amount" numeric, "p_reason" "text") RETURNS "public"."user_profile"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_profile public.user_profile;
  v_admin_id uuid;
  v_before numeric;
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
begin
  select id into v_admin_id
  from public.admin_user
  where user_id = auth.uid();

  if v_admin_id is null or not public.admin_has_permission('approve_transactions') then
    raise exception 'not authorized';
  end if;

  if p_user_id is null or p_amount is null or p_amount <= 0 then
    raise exception 'invalid funding request';
  end if;

  if v_reason is null then
    raise exception 'reason is required';
  end if;

  select * into v_profile
  from public.user_profile
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'user profile not found';
  end if;

  if v_profile.blocked then
    raise exception 'blocked user cannot receive funding';
  end if;

  v_before := v_profile.available_balance;

  update public.user_profile
  set available_balance = available_balance + p_amount,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_profile;

  insert into public.transaction
    (user_id,type,amount,status,method,note,approved_by,approval_status,approval_reason,approved_at,settled_at,created_at)
  values
    (p_user_id,'bonus',p_amount,'completed','admin',v_reason,v_admin_id,'approved',v_reason,now(),now(),now());

  insert into public.admin_action_audit
    (admin_id,user_id,action,target_id,old_values,new_values,reason,created_at)
  values
    (v_admin_id,p_user_id,'fund_user',p_user_id,
     jsonb_build_object('available_balance',v_before),
     jsonb_build_object('available_balance',v_profile.available_balance),
     v_reason,now());

  return v_profile;
end;
$$;


ALTER FUNCTION "public"."admin_fund_user"("p_user_id" "uuid", "p_amount" numeric, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_has_permission"("p_permission" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select exists (
    select 1
    from public.admin_user a
    where a.user_id = auth.uid()
      and p_permission = any(coalesce(a.permissions, '{}'::text[]))
  );
$$;


ALTER FUNCTION "public"."admin_has_permission"("p_permission" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_investment" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "plan_id" "text" NOT NULL,
    "principal" numeric(38,18) NOT NULL,
    "daily_rate" numeric(38,18) NOT NULL,
    "duration_days" integer NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_accrual_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "credited_profit" numeric(38,18) DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "daily_accrual_enabled" boolean DEFAULT true NOT NULL,
    "currency" "text" DEFAULT 'USD'::"text" NOT NULL,
    CONSTRAINT "user_investment_credited_profit_nonnegative" CHECK (("credited_profit" >= (0)::numeric)),
    CONSTRAINT "user_investment_currency_check" CHECK (("currency" = ANY (ARRAY['USD'::"text", 'BDX'::"text"]))),
    CONSTRAINT "user_investment_currency_usd_bdx_guard" CHECK (("currency" = ANY (ARRAY['USD'::"text", 'BDX'::"text"]))),
    CONSTRAINT "user_investment_daily_rate_check" CHECK (("daily_rate" >= (0)::numeric)),
    CONSTRAINT "user_investment_daily_rate_nonnegative" CHECK (("daily_rate" >= (0)::numeric)),
    CONSTRAINT "user_investment_duration_days_check" CHECK (("duration_days" > 0)),
    CONSTRAINT "user_investment_duration_positive" CHECK (("duration_days" > 0)),
    CONSTRAINT "user_investment_principal_check" CHECK (("principal" > (0)::numeric)),
    CONSTRAINT "user_investment_principal_positive" CHECK (("principal" > (0)::numeric)),
    CONSTRAINT "user_investment_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."user_investment" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_investment"."currency" IS 'Investment denomination. Legacy rows default to USD; USD and BDX amounts are never combined.';



CREATE OR REPLACE FUNCTION "public"."admin_manage_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_status" "text", "p_reason" "text") RETURNS "public"."user_investment"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_inv public.user_investment;
  v_profile public.user_profile;
  v_admin uuid := auth.uid();
  v_old_status text;
begin
  if not public.admin_has_permission('manage_users') then
    raise exception 'not authorized';
  end if;
  if p_daily_rate is null or p_daily_rate < 0 then
    raise exception 'invalid daily rate';
  end if;
  if p_status not in ('active','completed','cancelled') then
    raise exception 'invalid investment status';
  end if;
  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'reason is required';
  end if;

  select * into v_inv
  from public.user_investment
  where id = p_investment_id
  for update;

  if not found then raise exception 'investment not found'; end if;
  v_old_status := v_inv.status;

  select * into v_profile
  from public.user_profile
  where user_id = v_inv.user_id
  for update;

  if not found then raise exception 'user profile not found'; end if;
  if v_profile.blocked then raise exception 'blocked user cannot have investment managed'; end if;

  if v_old_status = 'active' and p_status in ('completed','cancelled') then
    update public.user_profile
    set locked_balance = greatest(0, locked_balance - v_inv.principal),
        available_balance = available_balance + v_inv.principal,
        updated_at = now()
    where user_id = v_inv.user_id;
  elsif v_old_status in ('completed','cancelled') and p_status = 'active' then
    if v_profile.available_balance < v_inv.principal then
      raise exception 'insufficient available balance';
    end if;
    update public.user_profile
    set available_balance = available_balance - v_inv.principal,
        locked_balance = locked_balance + v_inv.principal,
        updated_at = now()
    where user_id = v_inv.user_id;
  end if;

  update public.user_investment
  set daily_rate = p_daily_rate,
      status = p_status,
      completed_at = case
        when p_status in ('completed','cancelled') then coalesce(completed_at, now())
        else null
      end,
      updated_at = now()
  where id = p_investment_id
  returning * into v_inv;

  insert into public.admin_action_audit
    (admin_id, user_id, action, target_id, old_values, new_values, reason, created_at)
  values
    (v_admin, v_inv.user_id, 'manage_investment', v_inv.id,
     jsonb_build_object('status', v_old_status),
     jsonb_build_object('status', v_inv.status, 'daily_rate', v_inv.daily_rate),
     btrim(p_reason), now());

  return v_inv;
end;
$$;


ALTER FUNCTION "public"."admin_manage_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_status" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_reject_deposit"("p_transaction_id" "uuid", "p_reason" "text") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_tx public.transaction;
begin
  if not public.admin_has_permission('reject_transactions') then raise exception 'not authorized'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id;
  if not found or v_tx.type <> 'deposit' then raise exception 'deposit transaction not found'; end if;
  return public.admin_reject_transaction(p_transaction_id,p_reason);
end;
$$;


ALTER FUNCTION "public"."admin_reject_deposit"("p_transaction_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_reject_transaction"("p_transaction_id" "uuid", "p_reason" "text") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_admin public.admin_user; v_tx public.transaction; v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('reject_transactions') then raise exception 'Permission denied'; end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Rejection reason is required'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.approval_status<>'awaiting' then raise exception 'Transaction is not awaiting approval'; end if;

  v_currency := coalesce(v_tx.currency,'USD');
  if v_tx.type='withdraw' then
    if v_currency='BDX' then
      update public.user_profile set bdx_balance=bdx_balance+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
    else
      update public.user_profile set available_balance=available_balance+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
    end if;
  end if;

  update public.transaction set approval_status='rejected',status='failed',approved_by=v_admin.id,
    approval_reason=p_reason,approved_at=now(),updated_at=now() where id=p_transaction_id returning * into v_tx;
  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'rejected',jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status',v_tx.approval_status,'status',v_tx.status,'currency',v_currency),p_reason);
  return v_tx;
end;
$$;


ALTER FUNCTION "public"."admin_reject_transaction"("p_transaction_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_reject_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_tx public.transaction;
begin
  if not public.admin_has_permission('reject_transactions') then raise exception 'not authorized'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id;
  if not found or v_tx.type <> 'withdraw' then raise exception 'withdrawal transaction not found'; end if;
  return public.admin_reject_transaction(p_transaction_id,p_reason);
end;
$$;


ALTER FUNCTION "public"."admin_reject_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_search_users"("p_query" "text" DEFAULT ''::"text", "p_limit" integer DEFAULT 50) RETURNS TABLE("user_id" "uuid", "email" "text", "username" "text", "fullname" "text", "phone" "text", "country" "text", "kyc_status" "text", "available_balance" numeric, "locked_balance" numeric, "total_deposits" numeric, "total_withdrawals" numeric, "referral_earnings" numeric, "blocked" boolean, "blocked_reason" "text", "blocked_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_query text := lower(trim(coalesce(p_query,'')));
  v_limit integer := greatest(1, least(coalesce(p_limit,50),100));
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;

  return query
  select
    p.user_id,u.email::text,p.username,p.fullname,p.phone,p.country,p.kyc_status,
    p.available_balance,p.locked_balance,p.total_deposits,p.total_withdrawals,
    p.referral_earnings,p.blocked,p.blocked_reason,p.blocked_at,p.created_at
  from public.user_profile p
  join auth.users u on u.id=p.user_id
  where v_query=''
     or lower(coalesce(u.email,'')) like '%'||v_query||'%'
     or lower(coalesce(p.username,'')) like '%'||v_query||'%'
     or lower(coalesce(p.fullname,'')) like '%'||v_query||'%'
     or lower(coalesce(p.country,'')) like '%'||v_query||'%'
     or p.user_id::text like '%'||v_query||'%'
  order by p.created_at desc
  limit v_limit;
end;
$$;


ALTER FUNCTION "public"."admin_search_users"("p_query" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_search_users_bdx"("p_query" "text" DEFAULT ''::"text", "p_limit" integer DEFAULT 50) RETURNS TABLE("user_id" "uuid", "email" "text", "username" "text", "fullname" "text", "phone" "text", "country" "text", "kyc_status" "text", "available_balance" numeric, "locked_balance" numeric, "bdx_balance" numeric, "locked_bdx_balance" numeric, "total_deposits" numeric, "total_withdrawals" numeric, "referral_earnings" numeric, "blocked" boolean, "blocked_reason" "text", "blocked_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_query text := lower(trim(coalesce(p_query,''))); v_limit integer := greatest(1,least(coalesce(p_limit,50),100));
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then raise exception 'Permission denied'; end if;
  return query select p.user_id,u.email::text,p.username,p.fullname,p.phone,p.country,p.kyc_status,p.available_balance,p.locked_balance,p.bdx_balance,p.locked_bdx_balance,p.total_deposits,p.total_withdrawals,p.referral_earnings,p.blocked,p.blocked_reason,p.blocked_at,p.created_at
  from public.user_profile p join auth.users u on u.id=p.user_id
  where v_query='' or lower(coalesce(u.email,'')) like '%'||v_query||'%' or lower(coalesce(p.username,'')) like '%'||v_query||'%' or lower(coalesce(p.fullname,'')) like '%'||v_query||'%' or lower(coalesce(p.country,'')) like '%'||v_query||'%' or p.user_id::text like '%'||v_query||'%'
  order by p.created_at desc limit v_limit;
end;
$$;


ALTER FUNCTION "public"."admin_search_users_bdx"("p_query" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_user_block"("p_user_id" "uuid", "p_blocked" boolean, "p_reason" "text" DEFAULT NULL::"text") RETURNS "public"."user_profile"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_admin public.admin_user;
  v_old public.user_profile;
  v_new public.user_profile;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if p_user_id=auth.uid() then raise exception 'Administrators cannot block their own account'; end if;

  select * into v_old from public.user_profile where user_id=p_user_id for update;
  if v_old.user_id is null then raise exception 'User profile not found'; end if;

  update public.user_profile
  set blocked=p_blocked,
      blocked_reason=case when p_blocked then v_reason else null end,
      blocked_at=case when p_blocked then now() else null end,
      updated_at=now()
  where user_id=p_user_id
  returning * into v_new;

  insert into public.admin_action_audit(
    admin_id,user_id,action,target_id,old_values,new_values,reason
  )
  values(
    v_admin.id,p_user_id,
    case when p_blocked then 'user_blocked' else 'user_unblocked' end,
    p_user_id,
    jsonb_build_object('blocked',v_old.blocked,'blocked_reason',v_old.blocked_reason),
    jsonb_build_object('blocked',v_new.blocked,'blocked_reason',v_new.blocked_reason),
    v_reason
  );

  return v_new;
end;
$$;


ALTER FUNCTION "public"."admin_set_user_block"("p_user_id" "uuid", "p_blocked" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_settle_transaction"("p_transaction_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_admin public.admin_user; v_tx public.transaction; v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then raise exception 'Permission denied'; end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if not found then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then raise exception 'Only deposit and withdrawal can be settled'; end if;
  if v_tx.status='completed' then raise exception 'Transaction already completed'; end if;
  if v_tx.approval_status<>'approved' then raise exception 'Transaction must be approved first'; end if;
  v_currency := coalesce(v_tx.currency,'USD');
  if v_currency not in ('USD','BDX') then raise exception 'Unsupported transaction currency'; end if;
  if v_tx.type='deposit' then
    if v_currency='BDX' then
      update public.user_profile set bdx_balance=bdx_balance+v_tx.amount,total_deposits_bdx=total_deposits_bdx+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
    else
      update public.user_profile set available_balance=available_balance+v_tx.amount,total_deposits=total_deposits+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
    end if;
  elsif v_currency='BDX' then
    update public.user_profile set total_withdrawals_bdx=total_withdrawals_bdx+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
  else
    update public.user_profile set total_withdrawals=total_withdrawals+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
  end if;
  if not found then raise exception 'User profile not found during settlement'; end if;
  update public.transaction set status='completed',settled_at=now(),updated_at=now() where id=p_transaction_id returning * into v_tx;
  if v_tx.type='deposit' then perform public.credit_referral_for_deposit(v_tx.id); end if;
  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'settled',jsonb_build_object('status','pending'),jsonb_build_object('status',v_tx.status,'currency',v_currency),p_reason);
  return v_tx;
end;
$$;


ALTER FUNCTION "public"."admin_settle_transaction"("p_transaction_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_investment"("p_investment_id" "uuid", "p_daily_rate" numeric DEFAULT NULL::numeric, "p_daily_accrual_enabled" boolean DEFAULT NULL::boolean) RETURNS "public"."user_investment"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_admin public.admin_user;
  v_old public.user_investment;
  v_new public.user_investment;
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_old from public.user_investment where id=p_investment_id for update;
  if v_old.id is null then raise exception 'Investment not found'; end if;

  if p_daily_rate is not null and p_daily_rate < 0 then
    raise exception 'Daily rate cannot be negative';
  end if;

  update public.user_investment
  set daily_rate=coalesce(p_daily_rate,daily_rate),
      daily_accrual_enabled=coalesce(p_daily_accrual_enabled,daily_accrual_enabled),
      updated_at=now()
  where id=p_investment_id
  returning * into v_new;

  insert into public.admin_action_audit(
    admin_id,user_id,action,target_id,old_values,new_values,reason
  )
  values(
    v_admin.id,v_old.user_id,'investment_updated',p_investment_id,
    jsonb_build_object('daily_rate',v_old.daily_rate,'daily_accrual_enabled',v_old.daily_accrual_enabled),
    jsonb_build_object('daily_rate',v_new.daily_rate,'daily_accrual_enabled',v_new.daily_accrual_enabled),
    'Administrator updated investment accrual settings'
  );

  return v_new;
end;
$$;


ALTER FUNCTION "public"."admin_update_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_daily_accrual_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_user_can_transact"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_blocked boolean;
begin
  if p_user_id is null then
    raise exception 'Unauthorized';
  end if;

  select blocked into v_blocked
  from public.user_profile
  where user_id = p_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;

  if coalesce(v_blocked, false) then
    raise exception 'User account is blocked';
  end if;
end;
$$;


ALTER FUNCTION "public"."assert_user_can_transact"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buy_investment_plan"("p_plan_id" "text", "p_amount" numeric) RETURNS "public"."user_investment"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_plan public.investment_plan_catalog;
  v_profile public.user_profile;
  v_inv public.user_investment;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  perform public.assert_user_can_transact(v_uid);
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;

  select * into v_plan
  from public.investment_plan_catalog
  where id = p_plan_id and active;
  if v_plan.id is null then raise exception 'Investment plan not found'; end if;
  if p_amount < v_plan.min_amount then raise exception 'Minimum investment is % BDX',v_plan.min_amount; end if;
  if v_plan.max_amount is not null and p_amount > v_plan.max_amount then
    raise exception 'Maximum investment is % BDX',v_plan.max_amount;
  end if;

  select * into v_profile from public.user_profile where user_id = v_uid for update;
  if v_profile.user_id is null then raise exception 'Profile not found'; end if;
  if v_profile.bdx_balance < p_amount then raise exception 'Insufficient BDX balance'; end if;

  update public.user_profile
  set bdx_balance = bdx_balance - p_amount,
      locked_bdx_balance = locked_bdx_balance + p_amount,
      updated_at = now()
  where user_id = v_uid;

  insert into public.user_investment(user_id,plan_id,principal,daily_rate,duration_days,currency)
  values(v_uid,v_plan.id,p_amount,v_plan.daily_rate,v_plan.duration_days,'BDX')
  returning * into v_inv;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
  values(v_uid,'plan',p_amount,'BDX','completed','approved',v_plan.name,'BDX-denominated investment purchase');
  return v_inv;
end;
$$;


ALTER FUNCTION "public"."buy_investment_plan"("p_plan_id" "text", "p_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text" DEFAULT NULL::"text", "p_note" "text" DEFAULT NULL::"text", "p_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
declare
  v_tx public.transaction;
  v_uid uuid := auth.uid();
  v_address text := btrim(coalesce(p_note, ''));
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;

  if p_type not in ('deposit','withdraw') then
    raise exception 'Invalid transaction type';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if p_type = 'withdraw' then
    if p_method = 'Beldex' then
      if p_amount < 293.984 then
        raise exception 'Minimum Beldex withdrawal is 4000 BDX (293.984 USD)';
      end if;
    elsif p_amount < 300 then
      raise exception 'Minimum withdrawal is 300';
    end if;

    if p_method not in ('Bitcoin', 'Ethereum', 'Beldex') then
      raise exception 'Invalid withdrawal method';
    end if;

    if v_address = '' then
      raise exception 'Please enter a destination address';
    end if;

    if p_method = 'Ethereum' and v_address !~ '^0x[0-9A-Fa-f]{40}$' then
      raise exception 'Invalid Ethereum destination address';
    end if;

    if p_method = 'Bitcoin'
      and v_address !~* '^bc1[ac-hj-np-z02-9]{11,71}$'
      and v_address !~ '^[13][1-9A-HJ-NP-Za-km-z]{25,34}$'
    then
      raise exception 'Invalid Bitcoin destination address';
    end if;

    if p_method = 'Beldex'
      and (
        v_address !~ '^[1-9A-HJ-NP-Za-km-z]+$'
        or length(v_address) < 90
        or length(v_address) > 110
      )
    then
      raise exception 'Invalid Beldex destination address';
    end if;
  end if;

  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx
      from public.transaction
     where user_id = v_uid and request_id = p_request_id
     limit 1;
    if found then return v_tx; end if;
  end if;

  if p_type = 'withdraw' then
    update public.user_profile
      set available_balance = available_balance - p_amount, updated_at = now()
      where user_id = v_uid and available_balance >= p_amount;
    if not found then raise exception 'Insufficient balance'; end if;
  end if;

  insert into public.transaction(user_id,type,amount,status,approval_status,method,note,request_id)
  values (v_uid,p_type,p_amount,'pending','awaiting',p_method,v_address,p_request_id)
  returning * into v_tx;

  return v_tx;
exception
  when unique_violation then
    if p_request_id is not null then
      select * into v_tx
        from public.transaction
       where user_id = v_uid and request_id = p_request_id
       limit 1;
      if found then return v_tx; end if;
    end if;
    raise;
end;
$_$;


ALTER FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid", "p_currency" "text") RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_tx public.transaction;
  v_currency text := upper(coalesce(p_currency,'USD'));
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if p_type not in ('deposit','withdraw') then raise exception 'Invalid transaction type'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if v_currency not in ('BDX','USD') then raise exception 'Unsupported currency'; end if;
  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found then
      if v_tx.type <> p_type or v_tx.amount <> p_amount or coalesce(v_tx.currency,'USD') <> v_currency then
        raise exception 'Request ID was already used for a different transaction';
      end if;
      return v_tx;
    end if;
  end if;

  if p_type='withdraw' then
    if v_currency='BDX' then
      update public.user_profile set bdx_balance=bdx_balance-p_amount,updated_at=now()
      where user_id=v_uid and bdx_balance>=p_amount;
    else
      update public.user_profile set available_balance=available_balance-p_amount,updated_at=now()
      where user_id=v_uid and available_balance>=p_amount;
    end if;
    if not found then raise exception 'Insufficient % balance',v_currency; end if;
  end if;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note,request_id)
  values(v_uid,p_type,p_amount,v_currency,'pending','awaiting',p_method,p_note,p_request_id)
  returning * into v_tx;
  return v_tx;
exception when unique_violation then
  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found and v_tx.type=p_type and v_tx.amount=p_amount and coalesce(v_tx.currency,'USD')=v_currency then return v_tx; end if;
  end if;
  raise;
end;
$$;


ALTER FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid", "p_currency" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."credit_referral_for_deposit"("p_transaction_id" "uuid") RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_tx public.transaction; v_ref uuid; v_cut numeric; v_currency text;
begin
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if not found then raise exception 'Transaction not found'; end if;
  if v_tx.type <> 'deposit' or v_tx.status <> 'completed' then return 0; end if;
  v_currency := coalesce(v_tx.currency,'USD');
  if v_currency not in ('USD','BDX') then raise exception 'Unsupported referral currency'; end if;
  select referred_by_user_id into v_ref from public.user_profile where user_id=v_tx.user_id;
  if v_ref is null or v_ref=v_tx.user_id then return 0; end if;
  if exists(select 1 from public.transaction where type='referral' and method='Referral deposit '||v_tx.id::text) then return 0; end if;
  v_cut := round(v_tx.amount*0.10,18);
  if v_cut <= 0 then return 0; end if;
  if v_currency='BDX' then
    update public.user_profile set bdx_balance=bdx_balance+v_cut,referral_earnings_bdx=referral_earnings_bdx+v_cut,updated_at=now() where user_id=v_ref;
  else
    update public.user_profile set available_balance=available_balance+v_cut,referral_earnings=referral_earnings+v_cut,updated_at=now() where user_id=v_ref;
  end if;
  if not found then raise exception 'Referrer profile not found'; end if;
  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
  values(v_ref,'referral',v_cut,v_currency,'completed','approved','Referral deposit '||v_tx.id::text,'10% referral commission for '||v_currency||' deposit');
  return v_cut;
end;
$$;


ALTER FUNCTION "public"."credit_referral_for_deposit"("p_transaction_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_user_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.user_profile (
    user_id,
    username,
    fullname,
    phone,
    country
  )
  values (
    new.id,
    nullif(new.raw_user_meta_data->>'username',''),
    nullif(new.raw_user_meta_data->>'full_name',''),
    nullif(new.raw_user_meta_data->>'phone',''),
    nullif(new.raw_user_meta_data->>'country','')
  )
  on conflict (user_id) do update set
    username = coalesce(excluded.username, public.user_profile.username),
    fullname = coalesce(excluded.fullname, public.user_profile.fullname),
    phone = coalesce(excluded.phone, public.user_profile.phone),
    country = coalesce(excluded.country, public.user_profile.country),
    updated_at = now();

  return new;
end;
$$;


ALTER FUNCTION "public"."ensure_user_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text" DEFAULT ''::"text", "p_country" "text" DEFAULT ''::"text", "p_ref" "text" DEFAULT NULL::"text") RETURNS "public"."user_profile"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_profile public.user_profile;
  v_ref uuid;
  v_code text;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if coalesce(trim(p_username),'')='' then raise exception 'Username is required'; end if;

  if p_ref is not null and trim(p_ref)<>'' then
    select user_id into v_ref
    from public.user_profile
    where lower(username)=lower(trim(p_ref))
       or lower(coalesce(referral_code,''))=lower(trim(p_ref))
    limit 1;
    if v_ref=v_uid then raise exception 'Cannot refer yourself'; end if;
  end if;

  v_code := lower(regexp_replace(trim(p_username),'[^a-zA-Z0-9_-]','','g'));
  if v_code='' then v_code := substr(replace(v_uid::text,'-',''),1,12); end if;

  insert into public.user_profile(
    user_id,username,fullname,phone,country,referral_code,referred_by_user_id,updated_at
  )
  values(
    v_uid,trim(p_username),coalesce(nullif(trim(p_fullname),''),trim(p_username)),
    coalesce(p_phone,''),coalesce(p_country,''),v_code,v_ref,now()
  )
  on conflict (user_id) do update set
    username=coalesce(nullif(excluded.username,''),public.user_profile.username),
    fullname=coalesce(nullif(excluded.fullname,''),public.user_profile.fullname),
    phone=excluded.phone,
    country=excluded.country,
    referral_code=coalesce(public.user_profile.referral_code,excluded.referral_code),
    referred_by_user_id=coalesce(public.user_profile.referred_by_user_id,excluded.referred_by_user_id),
    updated_at=now()
  returning * into v_profile;

  if not exists (
    select 1 from public.transaction
    where user_id=v_uid and type='bonus' and method='Welcome Bonus'
  ) then
    update public.user_profile
      set available_balance=available_balance+3, updated_at=now()
      where user_id=v_uid
      returning * into v_profile;

    insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
    values(v_uid,'bonus',3,'completed','approved','Welcome Bonus','Server-side welcome bonus');
  end if;

  return v_profile;
end;
$$;


ALTER FUNCTION "public"."ensure_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text", "p_country" "text", "p_ref" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.admin_user a where a.user_id = (select auth.uid())
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_daily_investment_accrual"() RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user record;
  v_total numeric := 0;
  v_user_total numeric;
begin
  if current_user <> 'postgres' then raise exception 'Cron execution only'; end if;
  for v_user in
    select distinct ui.user_id
    from public.user_investment ui
    join public.user_profile up on up.user_id = ui.user_id
    where ui.status = 'active' and ui.daily_accrual_enabled = true and up.blocked = false
  loop
    begin
      v_user_total := public.accrue_user_investments(v_user.user_id);
      v_total := v_total + coalesce(v_user_total, 0);
    exception when others then
      raise warning 'Daily accrual failed for user %: %', v_user.user_id, sqlerrm;
    end;
  end loop;
  return v_total;
end;
$$;


ALTER FUNCTION "public"."run_daily_investment_accrual"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."swap_assets"("p_user_id" "uuid", "p_from" "text", "p_to" "text", "p_amount" numeric, "p_rate" numeric) RETURNS "public"."transaction"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_profile public.user_profile;
  v_out numeric;
  v_tx public.transaction;
begin
  if p_user_id is null then raise exception 'Unauthorized'; end if;
  perform public.assert_user_can_transact(p_user_id);

  if p_from not in('USD','BDX') or p_to not in('USD','BDX') or p_from=p_to then
    raise exception 'Invalid swap pair';
  end if;
  if p_amount is null or p_amount<=0 then
    raise exception 'Amount must be greater than zero';
  end if;
  if p_rate is null or p_rate<=0 then
    raise exception 'Invalid rate';
  end if;

  select * into v_profile
  from public.user_profile
  where user_id=p_user_id
  for update;

  if v_profile.user_id is null then raise exception 'Profile not found'; end if;

  if p_from='USD' then
    if v_profile.available_balance<p_amount then raise exception 'Insufficient USD balance'; end if;
    v_out:=p_amount/p_rate;

    update public.user_profile
    set available_balance=available_balance-p_amount,
        bdx_balance=bdx_balance+v_out,
        updated_at=now()
    where user_id=p_user_id;

    insert into public.transaction(
      user_id,type,amount,status,approval_status,method,note
    )
    values(
      p_user_id,'swap',p_amount,'completed','approved','USD → BDX',
      p_amount::text||' USD → '||round(v_out,4)::text||' BDX @ '||p_rate::text
    )
    returning * into v_tx;
  else
    if v_profile.bdx_balance<p_amount then raise exception 'Insufficient BDX balance'; end if;
    v_out:=p_amount*p_rate;

    update public.user_profile
    set bdx_balance=bdx_balance-p_amount,
        available_balance=available_balance+v_out,
        updated_at=now()
    where user_id=p_user_id;

    insert into public.transaction(
      user_id,type,amount,status,approval_status,method,note
    )
    values(
      p_user_id,'swap',v_out,'completed','approved','BDX → USD',
      p_amount::text||' BDX → '||round(v_out,2)::text||' USD @ '||p_rate::text
    )
    returning * into v_tx;
  end if;

  return v_tx;
end;
$$;


ALTER FUNCTION "public"."swap_assets"("p_user_id" "uuid", "p_from" "text", "p_to" "text", "p_amount" numeric, "p_rate" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text" DEFAULT ''::"text", "p_country" "text" DEFAULT ''::"text", "p_avatar_url" "text" DEFAULT NULL::"text") RETURNS "public"."user_profile"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare v_uid uuid:=auth.uid(); v_profile public.user_profile;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if coalesce(trim(p_username),'')='' then raise exception 'Username is required'; end if;
  update public.user_profile set username=trim(p_username),
    fullname=coalesce(nullif(trim(p_fullname),''),trim(p_username)),
    phone=coalesce(trim(p_phone),''),country=coalesce(trim(p_country),''),
    avatar_url=p_avatar_url,updated_at=now()
  where user_id=v_uid returning * into v_profile;
  if v_profile.user_id is null then raise exception 'Profile not found'; end if;
  return v_profile;
end;
$$;


ALTER FUNCTION "public"."update_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text", "p_country" "text", "p_avatar_url" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_action_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "admin_id" "uuid",
    "user_id" "uuid",
    "action" "text" NOT NULL,
    "target_id" "uuid",
    "old_values" "jsonb",
    "new_values" "jsonb",
    "reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."admin_action_audit" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_user" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'admin'::"text" NOT NULL,
    "permissions" "text"[] DEFAULT ARRAY[]::"text"[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admin_user_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'moderator'::"text", 'support'::"text"])))
);


ALTER TABLE "public"."admin_user" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."books" (
    "user_id" "uuid" NOT NULL,
    "available" numeric DEFAULT 0 NOT NULL,
    "bdx" numeric DEFAULT 0 NOT NULL,
    "locked" numeric DEFAULT 0 NOT NULL,
    "profit" numeric DEFAULT 0 NOT NULL,
    "bonus" numeric DEFAULT 0 NOT NULL,
    "referral_bonus" numeric DEFAULT 0 NOT NULL,
    "withdrawn" numeric DEFAULT 0 NOT NULL,
    "txs" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "plans" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "notices" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "tickets" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."books" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."investment_plan_catalog" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "min_amount" numeric(38,18) NOT NULL,
    "max_amount" numeric(38,18),
    "duration_days" integer NOT NULL,
    "daily_rate" numeric(38,18) NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "investment_plan_catalog_daily_rate_check" CHECK (("daily_rate" >= (0)::numeric)),
    CONSTRAINT "investment_plan_catalog_duration_days_check" CHECK (("duration_days" > 0)),
    CONSTRAINT "investment_plan_catalog_min_amount_check" CHECK (("min_amount" > (0)::numeric)),
    CONSTRAINT "investment_plan_daily_rate_nonnegative" CHECK (("daily_rate" >= (0)::numeric)),
    CONSTRAINT "investment_plan_duration_positive" CHECK (("duration_days" > 0)),
    CONSTRAINT "investment_plan_max_amount_valid" CHECK ((("max_amount" IS NULL) OR ("max_amount" >= "min_amount"))),
    CONSTRAINT "investment_plan_min_amount_positive" CHECK (("min_amount" > (0)::numeric))
);


ALTER TABLE "public"."investment_plan_catalog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transaction_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transaction_id" "uuid" NOT NULL,
    "admin_id" "uuid",
    "action" "text" NOT NULL,
    "old_values" "jsonb",
    "new_values" "jsonb",
    "reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "transaction_audit_action_check" CHECK (("action" = ANY (ARRAY['created'::"text", 'approved'::"text", 'rejected'::"text", 'settled'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."transaction_audit" OWNER TO "postgres";


ALTER TABLE ONLY "public"."admin_action_audit"
    ADD CONSTRAINT "admin_action_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_user"
    ADD CONSTRAINT "admin_user_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_user"
    ADD CONSTRAINT "admin_user_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."books"
    ADD CONSTRAINT "books_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."investment_plan_catalog"
    ADD CONSTRAINT "investment_plan_catalog_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transaction_audit"
    ADD CONSTRAINT "transaction_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transaction"
    ADD CONSTRAINT "transaction_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_investment"
    ADD CONSTRAINT "user_investment_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profile"
    ADD CONSTRAINT "user_profile_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profile"
    ADD CONSTRAINT "user_profile_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."user_profile"
    ADD CONSTRAINT "user_profile_username_key" UNIQUE ("username");



CREATE INDEX "admin_action_audit_admin_id_idx" ON "public"."admin_action_audit" USING "btree" ("admin_id");



CREATE INDEX "admin_action_audit_created_at_idx" ON "public"."admin_action_audit" USING "btree" ("created_at" DESC);



CREATE INDEX "admin_action_audit_user_id_idx" ON "public"."admin_action_audit" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "transaction_approval_status_idx" ON "public"."transaction" USING "btree" ("approval_status");



CREATE INDEX "transaction_approved_by_idx" ON "public"."transaction" USING "btree" ("approved_by");



CREATE INDEX "transaction_audit_admin_id_idx" ON "public"."transaction_audit" USING "btree" ("admin_id");



CREATE INDEX "transaction_audit_transaction_id_idx" ON "public"."transaction_audit" USING "btree" ("transaction_id");



CREATE INDEX "transaction_created_at_idx" ON "public"."transaction" USING "btree" ("created_at" DESC);



CREATE INDEX "transaction_status_idx" ON "public"."transaction" USING "btree" ("status");



CREATE INDEX "transaction_user_id_idx" ON "public"."transaction" USING "btree" ("user_id");



CREATE UNIQUE INDEX "transaction_user_request_id_uq" ON "public"."transaction" USING "btree" ("user_id", "request_id") WHERE ("request_id" IS NOT NULL);



CREATE UNIQUE INDEX "transaction_welcome_bonus_uq" ON "public"."transaction" USING "btree" ("user_id") WHERE (("type" = 'bonus'::"text") AND ("method" = 'Welcome Bonus'::"text"));



CREATE INDEX "user_investment_accrual_enabled_idx" ON "public"."user_investment" USING "btree" ("status", "daily_accrual_enabled", "last_accrual_at");



CREATE INDEX "user_investment_due_idx" ON "public"."user_investment" USING "btree" ("status", "last_accrual_at");



CREATE INDEX "user_investment_plan_id_idx" ON "public"."user_investment" USING "btree" ("plan_id");



CREATE INDEX "user_investment_user_status_idx" ON "public"."user_investment" USING "btree" ("user_id", "status");



CREATE INDEX "user_profile_blocked_idx" ON "public"."user_profile" USING "btree" ("blocked");



CREATE UNIQUE INDEX "user_profile_referral_code_uq" ON "public"."user_profile" USING "btree" ("referral_code") WHERE ("referral_code" IS NOT NULL);



CREATE INDEX "user_profile_referred_by_user_id_idx" ON "public"."user_profile" USING "btree" ("referred_by_user_id");



ALTER TABLE ONLY "public"."admin_action_audit"
    ADD CONSTRAINT "admin_action_audit_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "public"."admin_user"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_action_audit"
    ADD CONSTRAINT "admin_action_audit_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_user"
    ADD CONSTRAINT "admin_user_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."books"
    ADD CONSTRAINT "books_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."transaction"
    ADD CONSTRAINT "transaction_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."admin_user"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."transaction_audit"
    ADD CONSTRAINT "transaction_audit_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "public"."admin_user"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."transaction_audit"
    ADD CONSTRAINT "transaction_audit_transaction_id_fkey" FOREIGN KEY ("transaction_id") REFERENCES "public"."transaction"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."transaction"
    ADD CONSTRAINT "transaction_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_investment"
    ADD CONSTRAINT "user_investment_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."investment_plan_catalog"("id");



ALTER TABLE ONLY "public"."user_investment"
    ADD CONSTRAINT "user_investment_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_profile"
    ADD CONSTRAINT "user_profile_referred_by_user_id_fkey" FOREIGN KEY ("referred_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."user_profile"
    ADD CONSTRAINT "user_profile_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."admin_action_audit" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_action_audit_select" ON "public"."admin_action_audit" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



ALTER TABLE "public"."admin_user" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_user_select_own" ON "public"."admin_user" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."books" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "insert own book" ON "public"."books" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "investment_catalog_select_active_or_admin" ON "public"."investment_plan_catalog" FOR SELECT TO "authenticated" USING (("active" OR ( SELECT "public"."is_admin"() AS "is_admin")));



ALTER TABLE "public"."investment_plan_catalog" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read own book" ON "public"."books" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."transaction" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transaction_audit" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "transaction_audit_select" ON "public"."transaction_audit" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "transaction_select_own_or_admin" ON "public"."transaction" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR ( SELECT "public"."is_admin"() AS "is_admin")));



CREATE POLICY "update own book" ON "public"."books" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."user_investment" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_investment_select_own_or_admin" ON "public"."user_investment" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR ( SELECT "public"."is_admin"() AS "is_admin")));



ALTER TABLE "public"."user_profile" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_profile_select_own_or_admin" ON "public"."user_profile" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR ( SELECT "public"."is_admin"() AS "is_admin")));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."accrue_user_investments"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accrue_user_investments"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accrue_user_investments"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."user_profile" TO "service_role";
GRANT SELECT ON TABLE "public"."user_profile" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_adjust_balance"("p_user_id" "uuid", "p_delta" numeric, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_adjust_balance"("p_user_id" "uuid", "p_delta" numeric, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_adjust_balance"("p_user_id" "uuid", "p_delta" numeric, "p_reason" "text") TO "authenticated";



GRANT ALL ON TABLE "public"."transaction" TO "service_role";
GRANT SELECT ON TABLE "public"."transaction" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_approve_deposit"("p_transaction_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_approve_deposit"("p_transaction_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_approve_deposit"("p_transaction_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_approve_transaction"("p_transaction_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_approve_transaction"("p_transaction_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_approve_transaction"("p_transaction_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_approve_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_approve_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_approve_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_financial_reconciliation"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_financial_reconciliation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_financial_reconciliation"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_financial_reconciliation_v2"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_financial_reconciliation_v2"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_financial_reconciliation_v2"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_fund_user"("p_user_id" "uuid", "p_amount" numeric, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_fund_user"("p_user_id" "uuid", "p_amount" numeric, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_fund_user"("p_user_id" "uuid", "p_amount" numeric, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_has_permission"("p_permission" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_has_permission"("p_permission" "text") TO "service_role";



GRANT ALL ON TABLE "public"."user_investment" TO "service_role";
GRANT SELECT ON TABLE "public"."user_investment" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_manage_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_status" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_manage_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_status" "text", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_manage_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_status" "text", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_reject_deposit"("p_transaction_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_reject_deposit"("p_transaction_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_reject_deposit"("p_transaction_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_reject_transaction"("p_transaction_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_reject_transaction"("p_transaction_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_reject_transaction"("p_transaction_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_reject_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_reject_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_reject_withdrawal"("p_transaction_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_search_users"("p_query" "text", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_search_users"("p_query" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_search_users"("p_query" "text", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_search_users_bdx"("p_query" "text", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_search_users_bdx"("p_query" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_search_users_bdx"("p_query" "text", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_user_block"("p_user_id" "uuid", "p_blocked" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_user_block"("p_user_id" "uuid", "p_blocked" boolean, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_user_block"("p_user_id" "uuid", "p_blocked" boolean, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_settle_transaction"("p_transaction_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_settle_transaction"("p_transaction_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_settle_transaction"("p_transaction_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_daily_accrual_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_daily_accrual_enabled" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_investment"("p_investment_id" "uuid", "p_daily_rate" numeric, "p_daily_accrual_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_user_can_transact"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_user_can_transact"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."buy_investment_plan"("p_plan_id" "text", "p_amount" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."buy_investment_plan"("p_plan_id" "text", "p_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."buy_investment_plan"("p_plan_id" "text", "p_amount" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid", "p_currency" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid", "p_currency" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_financial_transaction"("p_type" "text", "p_amount" numeric, "p_method" "text", "p_note" "text", "p_request_id" "uuid", "p_currency" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."credit_referral_for_deposit"("p_transaction_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."credit_referral_for_deposit"("p_transaction_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ensure_user_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ensure_user_profile"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."ensure_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text", "p_country" "text", "p_ref" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ensure_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text", "p_country" "text", "p_ref" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text", "p_country" "text", "p_ref" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."run_daily_investment_accrual"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."swap_assets"("p_user_id" "uuid", "p_from" "text", "p_to" "text", "p_amount" numeric, "p_rate" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."swap_assets"("p_user_id" "uuid", "p_from" "text", "p_to" "text", "p_amount" numeric, "p_rate" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text", "p_country" "text", "p_avatar_url" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text", "p_country" "text", "p_avatar_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_user_profile"("p_username" "text", "p_fullname" "text", "p_phone" "text", "p_country" "text", "p_avatar_url" "text") TO "service_role";



GRANT MAINTAIN ON TABLE "public"."admin_action_audit" TO "anon";
GRANT SELECT,MAINTAIN ON TABLE "public"."admin_action_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."admin_action_audit" TO "service_role";



GRANT ALL ON TABLE "public"."admin_user" TO "service_role";
GRANT SELECT ON TABLE "public"."admin_user" TO "authenticated";



GRANT ALL ON TABLE "public"."books" TO "service_role";



GRANT ALL ON TABLE "public"."investment_plan_catalog" TO "service_role";
GRANT SELECT ON TABLE "public"."investment_plan_catalog" TO "authenticated";



GRANT ALL ON TABLE "public"."transaction_audit" TO "service_role";
GRANT SELECT ON TABLE "public"."transaction_audit" TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







