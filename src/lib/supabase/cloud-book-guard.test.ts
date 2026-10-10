import test from "node:test";
import assert from "node:assert/strict";
import { isCompleteCloudRefresh } from "./cloud-book-guard.ts";

const transactions = { data: [] };
const investments = { data: [] };

test("rejects a cloud refresh when the profile query returns no row", () => {
  assert.equal(
    isCompleteCloudRefresh({ data: null, error: null }, transactions, investments),
    false,
  );
});

test("rejects a cloud refresh when profile data is absent", () => {
  assert.equal(isCompleteCloudRefresh({}, transactions, investments), false);
});

test("rejects a cloud refresh when the profile query fails", () => {
  assert.equal(
    isCompleteCloudRefresh({ data: null, error: new Error("profile query failed") }, transactions, investments),
    false,
  );
});

test("rejects a cloud refresh when the transaction query fails", () => {
  assert.equal(
    isCompleteCloudRefresh(
      { data: { available_balance: 42 }, error: null },
      { data: null, error: new Error("transaction query failed") },
      investments,
    ),
    false,
  );
});

test("rejects a cloud refresh when the investments query fails", () => {
  assert.equal(
    isCompleteCloudRefresh(
      { data: { available_balance: 42 }, error: null },
      transactions,
      { data: null, error: new Error("investment query failed") },
    ),
    false,
  );
});

test("accepts a complete refresh with an existing profile and empty ledgers", () => {
  assert.equal(
    isCompleteCloudRefresh(
      { data: { available_balance: 42 }, error: null },
      transactions,
      investments,
    ),
    true,
  );
});
