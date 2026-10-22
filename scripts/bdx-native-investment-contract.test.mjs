import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync(new URL("../supabase/migrations/20261011054325_20261011010000_bdx_native_investments.sql", import.meta.url), "utf8");
const accountingMigration = readFileSync(new URL("../supabase/migrations/20261016090000_bdx_native_accounting_enforcement.sql", import.meta.url), "utf8");
const adminAccountingMigration = readFileSync(new URL("../supabase/migrations/20261016091000_bdx_admin_controls_and_reconciliation.sql", import.meta.url), "utf8");
const bdxOnlyCutover = readFileSync(new URL("../supabase/migrations/20261022120000_bdx_only_wallet_and_conversion.sql", import.meta.url), "utf8");
const catalog = readFileSync(new URL("../src/lib/platform/catalog.ts", import.meta.url), "utf8");
const utils = readFileSync(new URL("../src/lib/utils.ts", import.meta.url), "utf8");
const store = readFileSync(new URL("../src/lib/platform/store.ts", import.meta.url), "utf8");
const books = readFileSync(new URL("../src/lib/supabase/books.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../src/routes/admin.tsx", import.meta.url), "utf8");

// New investments are explicitly BDX-denominated; legacy records remain USD.
assert.match(migration, /add column if not exists currency text not null default 'USD'/);
assert.match(migration, /check \(currency in \('USD','BDX'\)\)/);
assert.match(accountingMigration, /bdx_balance>=p_amount/);
assert.match(accountingMigration, /raise exception 'Insufficient % balance'/);
assert.match(migration, /bdx_balance\s*=\s*bdx_balance\s*-\s*p_amount/);
assert.match(migration, /locked_bdx_balance\s*=\s*locked_bdx_balance\s*\+\s*p_amount/);
assert.match(migration, /daily_rate,duration_days,currency\)[\s\S]*'BDX'/);

// BDX and legacy USD investments accrue/return principal to the matching wallet.
assert.match(migration, /if v_inv\.currency\s*=\s*'BDX' then[\s\S]*bdx_balance\s*=\s*bdx_balance\s*\+\s*v_profit\s*\+\s*v_principal_return/);
assert.match(migration, /else[\s\S]*available_balance\s*=\s*available_balance\s*\+\s*v_profit\s*\+\s*v_principal_return/);
assert.match(migration, /locked_bdx_balance\s*=\s*case when v_done then greatest\(0,locked_bdx_balance\s*-\s*v_inv\.principal\)/);
assert.match(migration, /locked_balance\s*=\s*case when v_done then greatest\(0,locked_balance\s*-\s*v_inv\.principal\)/);
assert.match(migration, /last_accrual_at\s*=\s*least\(v_inv\.started_at\s*\+\s*make_interval\(days\s*=>\s*v_inv\.duration_days\),\s*v_now\)/);
assert.match(migration, /where user_id\s*=\s*v_uid and status\s*=\s*'active' and daily_accrual_enabled\s*=\s*true[\s\S]*for update/);
assert.match(migration, /if v_done then[\s\S]*'Investment principal returned'/);

// Client passes BDX amounts without converting through a market quote.
assert.match(store, /p_amount: amount/);
assert.doesNotMatch(store, /const usdAmount = amount \* liveQuote\.beldex\.usd/);
assert.match(books, /amount: num\(p\.principal\)/);
assert.doesNotMatch(books, /usdToBdx\(num\(p\.principal\)\)/);
assert.match(books, /creditedProfit: num\(p\.credited_profit\)/);
assert.match(books, /currency: p\.currency === "BDX" \? "BDX" : "USD"/);
assert.match(admin, /investment\.currency === "BDX" \? "BDX" : "USD"/);


assert.match(admin, /admin_search_users_bdx/);
assert.match(admin, /user\.locked_bdx_balance/);
assert.match(migration, /create or replace function public\.admin_search_users_bdx/);
assert.match(migration, /p\.locked_bdx_balance<0/);
assert.match(migration, /ui\.currency='USD'/);

// Published percentages are daily simple-interest rates for new investments.
assert.match(catalog, /profit: "1\.90% Daily ROI"/);
assert.match(catalog, /dailyPct: 1\.9,/);
assert.match(catalog, /const profit = amount \* \(plan\.dailyPct \/ 100\) \* plan\.durationDays/);
assert.match(accountingMigration, /when 'gns' then 0\.019(?:\s|$)/);
assert.match(accountingMigration, /when 'build' then 0\.0251(?:\s|$)/);
assert.match(accountingMigration, /when 'follow' then 0\.0392(?:\s|$)/);
assert.match(accountingMigration, /when 'apex' then 0\.0856(?:\s|$)/);
assert.match(accountingMigration, /when 'edifex' then 0\.1343(?:\s|$)/);
assert.match(accountingMigration, /when 'dixon' then 0\.1543(?:\s|$)/);
assert.match(accountingMigration, /when 'falcon' then 0\.2378(?:\s|$)/);
assert.match(accountingMigration, /Beldex transactions must be denominated in BDX/);
assert.match(accountingMigration, /drop function if exists public\.swap_assets/);
assert.doesNotMatch(store, /bdxToUsd|usdToBdx|swap-assets/);
assert.doesNotMatch(utils, /BDX_USD_RATE|bdxToUsd|usdToBdx/);
assert.match(adminAccountingMigration, /locked_bdx_balance=locked_bdx_balance-v_old.principal/);
assert.match(adminAccountingMigration, /Reference was already used for a different BDX adjustment/);
assert.match(adminAccountingMigration, /admin_financial_reconciliation_v3/);
assert.match(adminAccountingMigration, /recorded_referrals_bdx/);


assert.match(bdxOnlyCutover, /BDX cutover blocked: unresolved legacy USD deposit\/withdrawal exists/);
assert.match(bdxOnlyCutover, /Two distinct approved quote sources are required/);
assert.match(bdxOnlyCutover, /Market quotes differ by more than 2 percent/);
assert.match(bdxOnlyCutover, /Both market quotes must be no more than 10 minutes old/);
assert.match(bdxOnlyCutover, /financial_currency_conversion_profile_audit/);
assert.match(bdxOnlyCutover, /financial_currency_conversion_investment_audit/);
assert.match(bdxOnlyCutover, /available_balance=0/);
assert.match(bdxOnlyCutover, /locked_balance=0/);
assert.match(bdxOnlyCutover, /currency='BDX'/);
assert.match(bdxOnlyCutover, /Only BDX accounting is supported/);
assert.match(bdxOnlyCutover, /Minimum withdrawal is 76 BDX/);
assert.match(bdxOnlyCutover, /bdx_balance=bdx_balance\+40/);
assert.match(bdxOnlyCutover, /'bonus',40,'BDX','completed','approved','Welcome Bonus'/);
assert.match(bdxOnlyCutover, /round\(v_tx.amount\*0\.05,18\)/);
assert.match(bdxOnlyCutover, /'5% BDX referral reward for the first completed deposit'/);
assert.match(bdxOnlyCutover, /bdx_referral_policy_cutover/);
assert.match(bdxOnlyCutover, /t\.status='completed' and t\.currency='BDX'/);
assert.match(bdxOnlyCutover, /Shared profile aggregate counters can contain more than one currency/);
assert.match(bdxOnlyCutover, /coalesce\(t\.currency,'USD'\)='USD'/);
assert.match(bdxOnlyCutover, /total_deposits_bdx = p\.total_deposits_bdx \+ coalesce/);
assert.match(bdxOnlyCutover, /total_withdrawals_bdx = p\.total_withdrawals_bdx \+ coalesce/);
assert.match(bdxOnlyCutover, /grant execute on function public.execute_usd_to_bdx_conversion\(text,numeric,timestamptz,text,text,numeric,timestamptz,text\) to service_role/);
assert.match(bdxOnlyCutover, /grant execute on function public.create_financial_transaction\(text,numeric,text,text,uuid,text\) to authenticated/);
assert.match(bdxOnlyCutover, /Only BDX Beldex requests can be approved/);
assert.match(bdxOnlyCutover, /Only BDX Beldex requests can be rejected/);
assert.match(bdxOnlyCutover, /Legacy balance adjustments are disabled/);
assert.match(bdxOnlyCutover, /drop function if exists public\.swap_assets/);
assert.match(bdxOnlyCutover, /Legacy investment is read-only until the audited BDX conversion is completed/);
assert.match(bdxOnlyCutover, /historical transaction rows are intentionally preserved unchanged for audit/i);
assert.doesNotMatch(bdxOnlyCutover, /update public\.transaction\s+set\s+currency\s*=\s*'BDX'/i);

console.log("BDX investment accounting contract checks passed.");
