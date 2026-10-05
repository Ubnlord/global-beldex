import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const step = async (_name, fn) => fn();

test("security migration exposes only the intended swap executor", { skip: !url || !serviceKey }, async () => {

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const suffix = randomUUID();
  const password = "SecurityRegression!9" + suffix;
  const makeUser = async (label) => {
    const email = `security-test-${label}-${suffix}@example.invalid`;
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    assert.ifError(error);
    assert.ok(data.user?.id);
    return { id: data.user.id, email, password };
  };

  const users = {};
  try {
    users.normal = await makeUser("normal");
    users.blocked = await makeUser("blocked");
    users.adminNoPermission = await makeUser("admin-no-permission");
    users.admin = await makeUser("admin");

    for (const [label, user] of Object.entries(users)) {
      const { error } = await admin.from("user_profile").upsert({
        user_id: user.id,
        username: `security_${label}_${suffix.slice(0, 8)}`,
        fullname: `Security test ${label}`,
        blocked: label === "blocked",
        available_balance: 50000,
        locked_balance: 0,
      }, { onConflict: "user_id" });
      assert.ifError(error);
    }

    for (const [user, permissions] of [
      [users.adminNoPermission, []],
      [users.admin, ["manage_users", "approve_transactions", "reject_transactions"]],
    ]) {
      const { error } = await admin.from("admin_user").upsert({
        user_id: user.id,
        role: "admin",
        permissions,
      }, { onConflict: "user_id" });
      assert.ifError(error);
    }

    const clientFor = async (user) => {
      const client = createClient(url, process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      const { error } = await client.auth.signInWithPassword({
        email: user.email,
        password: user.password,
      });
      assert.ifError(error);
      return client;
    };

    await test.step("ordinary user cannot execute admin search", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("admin_search_users", { p_query: "", p_limit: 10 });
      assert.ok(error, "ordinary user unexpectedly executed admin_search_users");
    });

    await test.step("admin without manage_users cannot block another user", async () => {
      const client = await clientFor(users.adminNoPermission);
      const { error } = await client.rpc("admin_set_user_block", {
        p_user_id: users.normal.id,
        p_blocked: true,
        p_reason: "security regression test",
      });
      assert.ok(error, "admin without manage_users unexpectedly blocked a user");
    });

    await test.step("authorized admin can execute protected user management", async () => {
      const client = await clientFor(users.admin);
      const { error } = await client.rpc("admin_set_user_block", {
        p_user_id: users.normal.id,
        p_blocked: true,
        p_reason: "security regression test",
      });
      assert.ifError(error);
      const { error: restoreError } = await admin.from("user_profile")
        .update({ blocked: false })
        .eq("user_id", users.normal.id);
      assert.ifError(restoreError);
    });

    await test.step("blocked user cannot create a deposit", async () => {
      const client = await clientFor(users.blocked);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 100,
        p_method: "security-test",
        p_note: null,
        p_request_id: randomUUID(),
      });
      assert.ok(error, "blocked user unexpectedly created a financial transaction");
    });

    await test.step("blocked user cannot buy an investment plan", async () => {
      const client = await clientFor(users.blocked);
      const { error } = await client.rpc("buy_investment_plan", {
        p_plan_id: "gns",
        p_amount: 4000,
      });
      assert.ok(error, "blocked user unexpectedly purchased an investment");
    });

    await test.step("authenticated client cannot call the swap RPC directly", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("swap_assets", {
        p_user_id: users.normal.id,
        p_from: "USD",
        p_to: "BDX",
        p_amount: 1,
        p_rate: 1,
      });
      assert.ok(error, "authenticated client unexpectedly executed the service-only swap RPC");
    });

    await test.step("duplicate request_id is idempotent", async () => {
      const client = await clientFor(users.normal);
      const requestId = randomUUID();
      const first = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 125,
        p_method: "security-test",
        p_note: null,
        p_request_id: requestId,
      });
      assert.ifError(first.error);
      assert.ok(first.data?.id);

      const second = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 125,
        p_method: "security-test",
        p_note: null,
        p_request_id: requestId,
      });
      assert.ifError(second.error);
      assert.equal(second.data?.id, first.data?.id);

      const { data, error } = await admin.from("transaction")
        .select("id")
        .eq("user_id", users.normal.id)
        .eq("request_id", requestId);
      assert.ifError(error);
      assert.equal(data?.length, 1);
    });
  } finally {
    for (const user of Object.values(users)) {
      await admin.from("admin_user").delete().eq("user_id", user.id);
      await admin.from("user_profile").delete().eq("user_id", user.id);
      await admin.auth.admin.deleteUser(user.id);
    }
  }
});
