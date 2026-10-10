import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

test("ordinary hydration does not recreate missing server profiles", async () => {
  const shell = await read("../src/components/layout/app-shell.tsx");
  assert.doesNotMatch(shell, /ensureCloudProfile/);
  assert.match(shell, /Never create\/upsert a profile during ordinary hydration/);
});

test("confirmed signup applies sponsor referral metadata after session confirmation", async () => {
  const confirm = await read("../src/routes/auth/confirm.tsx");
  const auth = await read("../src/lib/supabase/auth.ts");
  assert.match(confirm, /completeAuthRedirect/);
  assert.match(confirm, /ensureCloudProfile\(result\.profile\)/);
  assert.match(auth, /ref: base\.ref/);
  assert.doesNotMatch(auth, /ref: row\.referral_code/);
});
