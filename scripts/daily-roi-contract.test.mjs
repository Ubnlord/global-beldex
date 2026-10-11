import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const catalog = readFileSync(new URL("../src/lib/platform/catalog.ts", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/migrations/20261011003000_daily_roi_rate_interpretation.sql", import.meta.url), "utf8");

const plans = [
  { id: "gns", rate: 1.90, days: 30 },
  { id: "build", rate: 2.51, days: 60 },
  { id: "follow", rate: 3.92, days: 60 },
  { id: "apex", rate: 8.56, days: 365 },
  { id: "edifex", rate: 13.43, days: 730 },
  { id: "dixon", rate: 15.43, days: 730 },
  { id: "falcon", rate: 23.78, days: 1825 },
];

for (const plan of plans) {
  assert.match(catalog, new RegExp(`dailyPct: ${plan.rate}\\s*,`), `${plan.id} should use the published percentage as its daily rate`);
  assert.ok(catalog.includes(`${plan.rate.toFixed(2)}% Daily ROI`), `${plan.id} should identify ROI as daily`);
  assert.ok(migration.includes(`when '${plan.id}' then ${plan.rate / 100}`), `${plan.id} database catalog rate should match frontend`);
}

const amount = 4000;
const dailyRate = 1.90;
const days = 30;
const dailyInterest = amount * dailyRate / 100;
const totalProfit = dailyInterest * days;
const finalTotal = amount + totalProfit;

assert.equal(dailyInterest, 76);
assert.equal(totalProfit, 2280);
assert.equal(finalTotal, 6280);
assert.match(catalog, /amount \* \(plan\.dailyPct \/ 100\) \* plan\.durationDays/);
assert.match(migration, /where status = 'active'/);
assert.match(migration, /set daily_rate = case plan_id/);
assert.match(migration, /does not retroactively recalculate credited profits or/);

console.log("Daily ROI contract passed: GNS 4,000 BDX => 76/day, 2,280 profit, 6,280 maturity total.");
