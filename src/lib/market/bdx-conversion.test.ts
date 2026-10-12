import test from "node:test";
import assert from "node:assert/strict";
import { validateFreshBdxQuote, convertUsdToBdx, bdxUsdDisplay } from "./bdx-conversion.ts";

const now = Date.parse("2026-10-12T12:00:00.000Z");
const policy = {
  nowMs: now,
  maxAgeMs: 30_000,
  allowedSources: ["website-coingecko-live", "website-kucoin-live"],
  minUsdPerBdx: 0.02,
  maxUsdPerBdx: 0.20,
};
const quote = {
  usdPerBdx: 0.0875,
  source: "website-coingecko-live",
  observedAt: "2026-10-12T11:59:45.000Z",
};

test("accepts a fresh approved website quote", () => {
  assert.equal(validateFreshBdxQuote(quote, policy).usdPerBdx, 0.0875);
});

test("rejects missing, cached/emergency, unapproved, stale and invalid quotes", () => {
  assert.throws(() => validateFreshBdxQuote(null, policy), /Fresh BDX market quote required/);
  assert.throws(() => validateFreshBdxQuote({ ...quote, source: "localStorage-cache" }, policy), /Unapproved/);
  assert.throws(() => validateFreshBdxQuote({ ...quote, source: "emergency-fallback" }, policy), /Unapproved/);
  assert.throws(() => validateFreshBdxQuote({ ...quote, observedAt: "2026-10-12T11:00:00.000Z" }, policy), /stale/);
  assert.throws(() => validateFreshBdxQuote({ ...quote, usdPerBdx: 0 }, policy), /bounds/);
  assert.throws(() => validateFreshBdxQuote({ ...quote, observedAt: "not-a-date" }, policy), /timestamp/);
});

test("converts using decimal arithmetic and preserves the original USD amount", () => {
  assert.deepEqual(convertUsdToBdx("100.00", "0.0875"), {
    originalUsd: "100.00",
    bdxUnits: "1142.857142857142857142",
    roundingRemainderUsd: "0",
  });
  assert.equal(convertUsdToBdx("1", "3").originalUsd, "1");
});

test("rejects malformed amounts, zero price and invalid scale", () => {
  assert.throws(() => convertUsdToBdx("-1", "0.1"), /decimal strings/);
  assert.throws(() => convertUsdToBdx("1", "0"), /positive/);
  assert.throws(() => convertUsdToBdx("1", "0.1", 40), /scale/);
});

test("fixed BDX units get a changing USD display value without changing units", () => {
  const units = "100";
  assert.equal(bdxUsdDisplay(units, 0.08), 8);
  assert.equal(bdxUsdDisplay(units, 0.10), 10);
  assert.equal(units, "100");
  assert.throws(() => bdxUsdDisplay(units, 0), /live market price/);
});

test("rounding remainder is reported for fractional BDX units", () => {
  const converted = convertUsdToBdx("1", "3", 2);
  assert.equal(converted.bdxUnits, "0.33");
  assert.notEqual(converted.roundingRemainderUsd, "0");
});
