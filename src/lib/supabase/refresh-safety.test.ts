import test from "node:test";
import assert from "node:assert/strict";
import { runWithFailureFallback } from "./refresh-safety.ts";

test("a rejected accrual refresh is contained and reports failure", async () => {
  let failureReported = false;
  const result = await runWithFailureFallback(
    async () => { throw new Error("network unavailable"); },
    () => { failureReported = true; },
  );
  assert.equal(result, null);
  assert.equal(failureReported, true);
});

test("a successful refresh returns its data without reporting failure", async () => {
  let failureReported = false;
  const result = await runWithFailureFallback(
    async () => ({ available: 42 }),
    () => { failureReported = true; },
  );
  assert.deepEqual(result, { available: 42 });
  assert.equal(failureReported, false);
});
