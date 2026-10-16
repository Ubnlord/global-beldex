import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_TEST_URL || process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_TEST_SERVICE_ROLE_KEY;

const step = async (_name, fn) => fn();

test("financial authorization and currency controls hold", { skip: !url || !serviceKey }, async () => {

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
      [users.admin, ["manage_users", "approve_transactions", "reject_transactions", "view_transactions"]],
    ]) {
      const { error } = await admin.from("admin_user").upsert({
        user_id: user.id,
        role: "admin",
        permissions,
      }, { onConflict: "user_id" });
      assert.ifError(error);
    }

    const clientFor = async (user) => {
      const client = createClient(url, process.env.SUPABASE_TEST_PUBLISHABLE_KEY || process.env.SUPABASE_TEST_ANON_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      const { error } = await client.auth.signInWithPassword({
        email: user.email,
        password: user.password,
      });
      assert.ifError(error);
      return client;
    };

    await step("ordinary user cannot execute admin search", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("admin_search_users", { p_query: "", p_limit: 10 });
      assert.ok(error, "ordinary user unexpectedly executed admin_search_users");
    });

    await step("admin without manage_users cannot block another user", async () => {
      const client = await clientFor(users.adminNoPermission);
      const { error } = await client.rpc("admin_set_user_block", {
        p_user_id: users.normal.id,
        p_blocked: true,
        p_reason: "security regression test",
      });
      assert.ok(error, "admin without manage_users unexpectedly blocked a user");
    });

    await step("admin without approval permission cannot adjust BDX", async () => {
      const client = await clientFor(users.adminNoPermission);
      const { error } = await client.rpc("admin_adjust_bdx_balance", {
        p_user_id: users.normal.id,
        p_delta: 1,
        p_reason: "permission regression test",
        p_reference: null,
      });
      assert.ok(error, "admin without approve_transactions unexpectedly adjusted BDX");
    });

    await step("authorized admin can adjust BDX with a BDX ledger record", async () => {
      const client = await clientFor(users.admin);
      const result = await client.rpc("admin_adjust_bdx_balance", {
        p_user_id: users.normal.id,
        p_delta: 10,
        p_reason: "BDX adjustment regression test",
        p_reference: "security-test",
      });
      assert.ifError(result.error);
      assert.equal(result.data?.currency, "BDX");
      const { data, error } = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(error);
      assert.equal(Number(data.bdx_balance), 10);
    });

    await step("admin without view_transactions cannot run financial reconciliation", async () => {
      const client = await clientFor(users.adminNoPermission);
      const { error } = await client.rpc("admin_financial_reconciliation_v3");
      assert.ok(error, "admin without view_transactions unexpectedly read reconciliation");
    });

    await step("authorized admin can run currency-separated reconciliation", async () => {
      const client = await clientFor(users.admin);
      const { data, error } = await client.rpc("admin_financial_reconciliation_v3");
      assert.ifError(error);
      assert.ok(Array.isArray(data));
    });

    await step("authorized admin can execute protected user management", async () => {
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

    await step("blocked user cannot create a deposit", async () => {
      const client = await clientFor(users.blocked);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 300,
        p_method: "Bitcoin",
        p_note: null,
        p_request_id: randomUUID(),
        p_currency: "USD",
      });
      assert.ok(error, "blocked user unexpectedly created a financial transaction");
    });

    await step("blocked user cannot buy an investment plan", async () => {
      const client = await clientFor(users.blocked);
      const { error } = await client.rpc("buy_investment_plan", {
        p_plan_id: "gns",
        p_amount: 4000,
      });
      assert.ok(error, "blocked user unexpectedly purchased an investment");
    });

    await step("blocked user cannot create a withdrawal", async () => {
      const client = await clientFor(users.blocked);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 300,
        p_method: "Bitcoin",
        p_note: "bc1qaaaaaaaaaaa",
        p_request_id: randomUUID(),
        p_currency: "USD",
      });
      assert.ok(error, "blocked user unexpectedly created a withdrawal");
    });

    await step("Beldex deposits below the 4000 BDX minimum are rejected", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 3999,
        p_method: "BELDEX",
        p_note: null,
        p_request_id: randomUUID(),
        p_currency: "BDX",
      });
      assert.ok(error, "Beldex deposit below 4000 BDX unexpectedly succeeded");
    });

    await step("USD payment-method deposits below the 300 USD minimum are rejected", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 299,
        p_method: "Bitcoin",
        p_note: null,
        p_request_id: randomUUID(),
        p_currency: "USD",
      });
      assert.ok(error, "USD deposit below 300 unexpectedly succeeded");
    });

    await step("Beldex requests cannot be recorded in USD", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 4000,
        p_method: "BELDEX",
        p_note: null,
        p_request_id: randomUUID(),
        p_currency: "USD",
      });
      assert.ok(error, "Beldex deposit unexpectedly accepted USD denomination");
    });

    await step("ordinary user cannot read another user's profile or transaction", async () => {
      const client = await clientFor(users.normal);
      const { data: profileRows, error: profileError } = await client
        .from("user_profile").select("user_id").eq("user_id", users.blocked.id);
      assert.ifError(profileError);
      assert.equal(profileRows?.length ?? 0, 0);

      const { data: txRows, error: txError } = await client
        .from("transaction").select("id").eq("user_id", users.blocked.id);
      assert.ifError(txError);
      assert.equal(txRows?.length ?? 0, 0);
    });

    await step("ordinary client cannot write protected financial/profile tables", async () => {
      const client = await clientFor(users.normal);

      const { error: txInsertError } = await client.from("transaction").insert({
        user_id: users.normal.id,
        type: "deposit",
        amount: 1,
        status: "pending",
        approval_status: "awaiting",
      });
      assert.ok(txInsertError, "ordinary client unexpectedly inserted a transaction");

      const { error: profileUpdateError } = await client.from("user_profile")
        .update({ available_balance: 999999999 })
        .eq("user_id", users.normal.id);
      assert.ok(profileUpdateError, "ordinary client unexpectedly updated a balance");
    });

    await step("withdrawal lifecycle is atomic and one-way", async () => {
      const client = await clientFor(users.normal);
      const initial = await admin.from("user_profile")
        .select("available_balance,total_withdrawals")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(initial.error);
      const initialBalance = Number(initial.data.available_balance);
      const initialWithdrawals = Number(initial.data.total_withdrawals || 0);

      const approveRequestId = randomUUID();
      const created = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 300,
        p_method: "Ethereum",
        p_note: "0x1111111111111111111111111111111111111111",
        p_request_id: approveRequestId,
        p_currency: "USD",
      });
      assert.ifError(created.error);
      assert.ok(created.data?.id);
      assert.equal(created.data?.status, "pending");
      assert.equal(created.data?.approval_status, "awaiting");

      const afterCreate = await admin.from("user_profile")
        .select("available_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(afterCreate.error);
      assert.equal(Number(afterCreate.data.available_balance), initialBalance - 300);

      const normalApprove = await client.rpc("admin_approve_transaction", {
        p_transaction_id: created.data.id,
        p_reason: "security lifecycle approval test",
      });
      assert.ok(normalApprove.error, "ordinary user unexpectedly approved a withdrawal");

      const noPermissionAdmin = await clientFor(users.adminNoPermission);
      const deniedApprove = await noPermissionAdmin.rpc("admin_approve_transaction", {
        p_transaction_id: created.data.id,
        p_reason: "security lifecycle permission test",
      });
      assert.ok(deniedApprove.error, "admin without approval permission unexpectedly approved a withdrawal");

      const approved = await admin.from("transaction")
        .select("approval_status,status")
        .eq("id", created.data.id)
        .single();
      assert.ifError(approved.error);
      assert.equal(approved.data.approval_status, "awaiting");
      assert.equal(approved.data.status, "pending");

      const adminClient = await clientFor(users.admin);
      const approvedByAdmin = await adminClient.rpc("admin_approve_transaction", {
        p_transaction_id: created.data.id,
        p_reason: "security lifecycle approval test",
      });
      assert.ifError(approvedByAdmin.error);
      assert.equal(approvedByAdmin.data?.approval_status, "approved");
      assert.equal(approvedByAdmin.data?.status, "pending");

      const doubleApprove = await adminClient.rpc("admin_approve_transaction", {
        p_transaction_id: created.data.id,
        p_reason: "duplicate approval must fail",
      });
      assert.ok(doubleApprove.error, "withdrawal was approved twice");

      const settled = await adminClient.rpc("admin_settle_transaction", {
        p_transaction_id: created.data.id,
        p_reason: "security lifecycle settlement test",
      });
      assert.ifError(settled.error);
      assert.equal(settled.data?.status, "completed");
      assert.equal(settled.data?.approval_status, "approved");

      const doubleSettle = await adminClient.rpc("admin_settle_transaction", {
        p_transaction_id: created.data.id,
        p_reason: "duplicate settlement must fail",
      });
      assert.ok(doubleSettle.error, "withdrawal was settled twice");

      const afterSettlement = await admin.from("user_profile")
        .select("available_balance,total_withdrawals")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(afterSettlement.error);
      assert.equal(Number(afterSettlement.data.available_balance), initialBalance - 300);
      assert.equal(Number(afterSettlement.data.total_withdrawals), initialWithdrawals + 300);

      const rejectRequestId = randomUUID();
      const rejectCreated = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 300,
        p_method: "Bitcoin",
        p_note: "bc1qaaaaaaaaaaa",
        p_request_id: rejectRequestId,
        p_currency: "USD",
      });
      assert.ifError(rejectCreated.error);
      assert.ok(rejectCreated.data?.id);

      const afterSecondCreate = await admin.from("user_profile")
        .select("available_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(afterSecondCreate.error);
      assert.equal(Number(afterSecondCreate.data.available_balance), initialBalance - 600);

      const rejected = await adminClient.rpc("admin_reject_transaction", {
        p_transaction_id: rejectCreated.data.id,
        p_reason: "security lifecycle rejection test",
      });
      assert.ifError(rejected.error);
      assert.equal(rejected.data?.approval_status, "rejected");
      assert.equal(rejected.data?.status, "failed");

      const doubleReject = await adminClient.rpc("admin_reject_transaction", {
        p_transaction_id: rejectCreated.data.id,
        p_reason: "duplicate rejection must fail",
      });
      assert.ok(doubleReject.error, "withdrawal was rejected twice");

      const afterRejection = await admin.from("user_profile")
        .select("available_balance,total_withdrawals")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(afterRejection.error);
      assert.equal(Number(afterRejection.data.available_balance), initialBalance - 300);
      assert.equal(Number(afterRejection.data.total_withdrawals), initialWithdrawals + 300);
    });

    await step("concurrent withdrawals reserve a balance only once", async () => {
      const before = await admin.from("user_profile")
        .select("available_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(before.error);
      const requestIds = [randomUUID(), randomUUID()];
      const [clientA, clientB] = await Promise.all([clientFor(users.normal), clientFor(users.normal)]);
      const results = await Promise.all(requestIds.map((requestId, index) =>
        (index === 0 ? clientA : clientB).rpc("create_financial_transaction", {
          p_type: "withdraw",
          p_amount: 30000,
          p_method: "Bitcoin",
          p_note: "bc1qaaaaaaaaaaa",
          p_request_id: requestId,
          p_currency: "USD",
        })
      ));
      assert.equal(results.filter((result) => !result.error).length, 1);
      assert.equal(results.filter((result) => result.error).length, 1);
      const after = await admin.from("user_profile")
        .select("available_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(after.error);
      assert.equal(Number(before.data.available_balance) - Number(after.data.available_balance), 30000);
      const { data, error } = await admin.from("transaction")
        .select("id")
        .eq("user_id", users.normal.id)
        .in("request_id", requestIds);
      assert.ifError(error);
      assert.equal(data?.length, 1);
    });

    await step("concurrent settlement credits totals and audit once", async () => {
      const client = await clientFor(users.normal);
      const requestId = randomUUID();
      const created = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 300,
        p_method: "Bitcoin",
        p_note: "bc1qaaaaaaaaaaa",
        p_request_id: requestId,
        p_currency: "USD",
      });
      assert.ifError(created.error);
      const adminClientA = await clientFor(users.admin);
      const adminClientB = await clientFor(users.admin);
      const approved = await adminClientA.rpc("admin_approve_transaction", {
        p_transaction_id: created.data.id,
        p_reason: "concurrency test approval",
      });
      assert.ifError(approved.error);
      const before = await admin.from("user_profile")
        .select("total_withdrawals")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(before.error);
      const results = await Promise.all([
        adminClientA.rpc("admin_settle_transaction", { p_transaction_id: created.data.id, p_reason: "concurrent settlement A" }),
        adminClientB.rpc("admin_settle_transaction", { p_transaction_id: created.data.id, p_reason: "concurrent settlement B" }),
      ]);
      assert.equal(results.filter((result) => !result.error).length, 1);
      assert.equal(results.filter((result) => result.error).length, 1);
      const after = await admin.from("user_profile")
        .select("total_withdrawals")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(after.error);
      assert.equal(Number(after.data.total_withdrawals) - Number(before.data.total_withdrawals), 300);
      const { data: auditRows, error: auditError } = await admin.from("transaction_audit")
        .select("id")
        .eq("transaction_id", created.data.id)
        .eq("action", "settled");
      assert.ifError(auditError);
      assert.equal(auditRows?.length, 1);
    });

    await step("duplicate request_id is idempotent", async () => {
      const client = await clientFor(users.normal);
      const requestId = randomUUID();
      const first = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 300,
        p_method: "Bitcoin",
        p_note: null,
        p_request_id: requestId,
        p_currency: "USD",
      });
      assert.ifError(first.error);
      assert.ok(first.data?.id);

      const second = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 300,
        p_method: "Bitcoin",
        p_note: null,
        p_request_id: requestId,
        p_currency: "USD",
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
