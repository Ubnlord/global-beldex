import assert from "node:assert/strict";
import fs from "node:fs";
import { Client } from "pg";

const connectionString = process.env.DB_URL;
if (!connectionString) throw new Error("DB_URL is required; run only against the disposable local Supabase database");

const userId = "a2300000-0000-4000-8000-000000000030";
const email = "plan-limit-migration-compatibility@example.test";
const client = new Client({ connectionString });
const migration = fs.readFileSync(new URL("../migrations/0030_restore_bdx_investment_plan_limits.sql", import.meta.url), "utf8");

const expected = [
  ["gns", 4000, 10000],
  ["build", 11000, 16000],
  ["follow", 17000, 30000],
  ["apex", 40000, 80000],
  ["edifex", 90000, 150000],
  ["dixon", 160000, 220000],
  ["falcon", 220000, 1000000],
];

async function financialSnapshot() {
  const profile = await client.query(
    "select to_jsonb(p) as row from public.user_profile p where user_id=$1",
    [userId],
  );
  const investments = await client.query(
    "select to_jsonb(i) as row from public.user_investment i where user_id=$1 order by id",
    [userId],
  );
  const transactions = await client.query(
    "select to_jsonb(t) as row from public.transaction t where user_id=$1 order by id",
    [userId],
  );
  return {
    profile: profile.rows.map((r) => r.row),
    investments: investments.rows.map((r) => r.row),
    transactions: transactions.rows.map((r) => r.row),
  };
}

await client.connect();
try {
  // Dedicated synthetic identity; never use a real customer ID.
  await client.query(
    `insert into auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) values ($1,'authenticated','authenticated',$2,'',now(),'{}'::jsonb,'{}'::jsonb,now(),now())
    on conflict (id) do nothing`,
    [userId, email],
  );
  await client.query(
    `insert into public.user_profile(user_id,available_balance,locked_balance,bdx_balance,locked_bdx_balance)
     values ($1,123.456,50.25,789.125,200.5)
     on conflict (user_id) do update set available_balance=123.456,locked_balance=50.25,
       bdx_balance=789.125,locked_bdx_balance=200.5`,
    [userId],
  );
  await client.query(
    `insert into public.user_investment(
      user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,status,daily_accrual_enabled,currency
    ) values ($1,'gns',50.25,0.019,30,now()-interval '1 day',now()-interval '1 day','active',true,'USD')`,
    [userId],
  );
  await client.query(
    `insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
     values ($1,'plan',50.25,'USD','completed','approved','GNS','synthetic migration compatibility fixture')`,
    [userId],
  );

  const before = await financialSnapshot();
  assert.equal(before.profile.length, 1, "synthetic profile exists before migration replay");
  assert.equal(before.investments.length, 1, "synthetic existing investment exists before migration replay");
  assert.equal(before.transactions.length, 1, "synthetic historical ledger row exists before migration replay");

  // Execute the exact migration file under test against the isolated test DB.
  await client.query(migration);

  const after = await financialSnapshot();
  assert.deepEqual(after, before, "plan-limit migration must not rewrite profile balances, existing investments, or transaction history");

  const catalog = await client.query(
    "select id,min_amount,max_amount from public.investment_plan_catalog where id = any($1::text[]) order by id",
    [expected.map(([id]) => id)],
  );
  const actual = new Map(catalog.rows.map((r) => [r.id, [Number(r.min_amount), Number(r.max_amount)]]));
  for (const [id, min, max] of expected) {
    assert.deepEqual(actual.get(id), [min, max], `${id} limits match the reviewed BDX-denominated plan limits`);
  }
  assert.equal(catalog.rows.length, expected.length, "all seven expected plans exist");

  console.log("PASS: migration replay changed only investment_plan_catalog limits/updated_at.");
  console.log("PASS: synthetic USD/BDX balances, existing investment row, and historical transaction remained byte-for-byte equivalent as JSON.");
  console.log("PASS: all seven BDX minimum/maximum limits match expected values.");
} finally {
  // Clean up only this fixed synthetic fixture identity in the disposable DB.
  await client.query("delete from public.transaction where user_id=$1", [userId]).catch(() => {});
  await client.query("delete from public.user_investment where user_id=$1", [userId]).catch(() => {});
  await client.query("delete from public.user_profile where user_id=$1", [userId]).catch(() => {});
  await client.query("delete from auth.users where id=$1", [userId]).catch(() => {});
  await client.end();
}
