import test from "node:test";
import assert from "node:assert/strict";
import { isCompleteCloudRefresh } from "./cloud-book-guard.ts";

const profile = {
  data: {
    available_balance: 42,
    locked_balance: 10,
    total_withdrawals: 3,
    bdx_balance: 5,
    referral_earnings: 2,
  },
  error: null,
};
const transactions = { data: [], error: null };
const investments = { data: [], error: null };

test("rejects a cloud refresh when the profile query returns no row", () => {
  assert.equal(isCompleteCloudRefresh({ data: null, error: null }, transactions, investments), false);
});

test("rejects a cloud refresh when profile data is absent", () => {
  assert.equal(isCompleteCloudRefresh({}, transactions, investments), false);
});

test("rejects a cloud refresh when the profile query fails", () => {
  assert.equal(isCompleteCloudRefresh({ data: null, error: new Error("profile query failed") }, transactions, investments), false);
});

test("rejects a cloud refresh when a required balance field is missing or invalid", () => {
  for (const value of [
    { ...profile.data, available_balance: undefined },
    { ...profile.data, locked_balance: null },
    { ...profile.data, bdx_balance: "not-a-number" },
  ]) {
    assert.equal(isCompleteCloudRefresh({ data: value, error: null }, transactions, investments), false);
  }
});

test("rejects a cloud refresh when transaction data is null, missing, or not an array", () => {
  for (const result of [{ data: null, error: null }, { error: null }, { data: {}, error: null }]) {
    assert.equal(isCompleteCloudRefresh(profile, result, investments), false);
  }
});

test("rejects a cloud refresh when the transaction query fails", () => {
  assert.equal(isCompleteCloudRefresh(profile, { data: null, error: new Error("transaction query failed") }, investments), false);
});

test("rejects a cloud refresh when investment data is null, missing, or not an array", () => {
  for (const result of [{ data: null, error: null }, { error: null }, { data: {}, error: null }]) {
    assert.equal(isCompleteCloudRefresh(profile, transactions, result), false);
  }
});

test("rejects a cloud refresh when the investments query fails", () => {
  assert.equal(isCompleteCloudRefresh(profile, transactions, { data: null, error: new Error("investment query failed") }), false);
});

test("accepts a complete refresh with an existing profile and genuinely empty ledgers", () => {
  assert.equal(isCompleteCloudRefresh(profile, transactions, investments), true);
});

test("accepts numeric strings returned by Postgres numeric columns", () => {
  assert.equal(isCompleteCloudRefresh({
    data: { ...profile.data, available_balance: "42.00" },
    error: null,
  }, transactions, investments), true);
});
