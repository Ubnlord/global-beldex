import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync(new URL("../supabase/migrations/20261011010000_bdx_native_investments.sql", import.meta.url), "utf8");
const store = readFileSync(new URL("../src/lib/platform/store.ts", import.meta.url), "utf8");
const books = readFileSync(new URL("../src/lib/supabase/books.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../src/routes/admin.tsx", import.meta.url), "utf8");

// New investments are explicitly BDX-denominated; legacy records remain USD.
assert.match(migration, /add column if not exists currency text not null default 'USD'/);
assert.match(migration, /check \(currency in \('USD','BDX'\)\)/);
assert.match(migration, /if v_profile\.bdx_balance<p_amount then raise exception 'Insufficient BDX balance'/);
assert.match(migration, /bdx_balance=bdx_balance-p_amount/);
assert.match(migration, /locked_bdx_balance=locked_bdx_balance\+p_amount/);
assert.match(migration, /daily_rate,duration_days,currency\)[\s\S]*'BDX'/);

// BDX and legacy USD investments accrue/return principal to the matching wallet.
assert.match(migration, /if v_inv\.currency='BDX' then[\s\S]*bdx_balance=bdx_balance\+v_profit\+v_principal_return/);
assert.match(migration, /else[\s\S]*available_balance=available_balance\+v_profit\+v_principal_return/);
assert.match(migration, /locked_bdx_balance=case when v_done then greatest\(0,locked_bdx_balance-v_inv\.principal\)/);
assert.match(migration, /locked_balance=case when v_done then greatest\(0,locked_balance-v_inv\.principal\)/);
assert.match(migration, /last_accrual_at=least\(v_inv\.started_at\+make_interval\(days=>v_inv\.duration_days\),v_now\)/);
assert.match(migration, /where user_id=v_uid and status='active' and daily_accrual_enabled=true[\s\S]*for update/);
assert.match(migration, /if v_done then[\s\S]*'Investment principal returned'/);

// Client passes BDX amounts without converting through a market quote.
assert.match(store, /p_amount: amount/);
assert.doesNotMatch(store, /const usdAmount = amount \* liveQuote\.beldex\.usd/);
assert.match(books, /amount: p\.currency === "BDX" \? num\(p\.principal\) : usdToBdx/);
assert.match(books, /currency: p\.currency === "BDX" \? "BDX" : "USD"/);
assert.match(admin, /investment\.currency === "BDX" \? "BDX" : "USD"/);


assert.match(admin, /admin_search_users_bdx/);
assert.match(admin, /user\\.locked_bdx_balance/);
assert.match(migration, /create or replace function public\\.admin_search_users_bdx/);
assert.match(migration, /p\\.locked_bdx_balance<0/);
assert.match(migration, /ui\\.currency='USD'/);

console.log("BDX investment accounting contract checks passed.");
