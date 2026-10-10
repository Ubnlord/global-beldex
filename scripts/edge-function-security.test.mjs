import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const source = fs.readFileSync(
  path.join(process.cwd(), "supabase/functions/swap-assets/index.ts"),
  "utf8",
);

test("swap Edge Function restricts browser origins", () => {
  assert.match(source, /const allowedOrigins = new Set\(/);
  assert.match(source, /"https:\/\/global-beldex\.com"/);
  assert.match(source, /"http:\/\/localhost:8080"/);
  assert.match(source, /"http:\/\/127\.0\.0\.1:8080"/);
  assert.match(source, /if \(origin && !allowedOrigins\.has\(origin\)\)/);
  assert.match(source, /headers\["Access-Control-Allow-Origin"\] = origin/);
  assert.match(source, /"Vary": "Origin"/);
  assert.doesNotMatch(source, /"Access-Control-Allow-Origin": "\*"/);
  assert.match(source, /Swap could not be completed\. Please try again\./);
  assert.doesNotMatch(source, /throw new Error\(error\.message\)/);
});
