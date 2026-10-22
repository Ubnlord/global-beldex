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
        bdx_balance: label === "blocked" ? 5000 : 0,
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

    await step("admin-console BDX adjustment RPC writes one balance change, transaction, and matching audit; replay is idempotent", async () => {
      const client = await clientFor(users.admin);
      const adjustment = {
        p_user_id: users.normal.id,
        p_delta: 10,
        p_reason: "BDX adjustment regression test",
        p_reference: `security-test-${suffix}`,
      };

      // This uses the same Supabase RPC name and named arguments as the admin
      // console, against the isolated migrated schema and a signed-in admin.
      const first = await client.rpc("admin_adjust_bdx_balance", adjustment);
      assert.ifError(first.error);
      assert.ok(first.data?.id, "RPC must return the created transaction");
      assert.equal(first.data.currency, "BDX");
      assert.equal(Number(first.data.amount), 10);
      assert.equal(first.data.type, "bonus");
      assert.equal(first.data.method, "Admin BDX adjustment");
      assert.equal(first.data.status, "completed");
      assert.equal(first.data.note, `BDX adjustment regression test | Ref: ${adjustment.p_reference}`);

      const profileAfterFirst = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(profileAfterFirst.error);
      assert.equal(Number(profileAfterFirst.data.bdx_balance), 10);

      const transactionRows = await admin.from("transaction")
        .select("id,user_id,type,amount,currency,status,method,note,request_id,approved_by")
        .eq("id", first.data.id)
        .eq("user_id", users.normal.id);
      assert.ifError(transactionRows.error);
      assert.equal(transactionRows.data?.length, 1);
      assert.equal(transactionRows.data[0].currency, "BDX");
      assert.equal(Number(transactionRows.data[0].amount), 10);
      assert.equal(transactionRows.data[0].method, "Admin BDX adjustment");
      assert.equal(transactionRows.data[0].status, "completed");

      const auditAfterFirst = await admin.from("admin_action_audit")
        .select("admin_id,user_id,action,target_id,old_values,new_values,reason")
        .eq("target_id", first.data.id)
        .eq("action", "bdx_balance_adjusted");
      assert.ifError(auditAfterFirst.error);
      assert.equal(auditAfterFirst.data?.length, 1, "exactly one matching audit row is required");
      assert.equal(auditAfterFirst.data[0].user_id, users.normal.id);
      assert.equal(auditAfterFirst.data[0].reason, adjustment.p_reason);
      assert.equal(Number(auditAfterFirst.data[0].old_values.bdx_balance), 0);
      assert.equal(Number(auditAfterFirst.data[0].new_values.bdx_balance), 10);
      assert.equal(Number(auditAfterFirst.data[0].new_values.delta), 10);
      assert.equal(auditAfterFirst.data[0].new_values.currency, "BDX");
      assert.equal(auditAfterFirst.data[0].new_values.reference, adjustment.p_reference);

      // Replay the exact console request: it must return the original row and
      // leave the balance, transaction count, and audit count unchanged.
      const replay = await client.rpc("admin_adjust_bdx_balance", adjustment);
      assert.ifError(replay.error);
      assert.equal(replay.data?.id, first.data.id, "idempotent replay must return original transaction");
      const [profileAfterReplay, transactionsAfterReplay, auditAfterReplay] = await Promise.all([
        admin.from("user_profile").select("bdx_balance").eq("user_id", users.normal.id).single(),
        admin.from("transaction").select("id", { count: "exact", head: true })
          .eq("user_id", users.normal.id).eq("request_id", first.data.request_id),
        admin.from("admin_action_audit").select("target_id", { count: "exact", head: true })
          .eq("target_id", first.data.id).eq("action", "bdx_balance_adjusted"),
      ]);
      assert.ifError(profileAfterReplay.error);
      assert.ifError(transactionsAfterReplay.error);
      assert.ifError(auditAfterReplay.error);
      assert.equal(Number(profileAfterReplay.data.bdx_balance), 10);
      assert.equal(transactionsAfterReplay.count, 1, "replay must not create a duplicate transaction");
      assert.equal(auditAfterReplay.count, 1, "replay must not create a duplicate audit row");
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
        p_amount: 4000,
        p_method: "Beldex",
        p_note: null,
        p_request_id: randomUUID(),
        p_currency: "BDX",
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

    await step("blocked user cannot create a withdrawal even with sufficient BDX", async () => {
      const client = await clientFor(users.blocked);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 300,
        p_method: "Beldex",
        p_note: "A".repeat(95),
        p_request_id: randomUUID(),
        p_currency: "BDX",
      });
      assert.ok(error, "blocked user unexpectedly created a withdrawal");
    });

    await step("Beldex deposits below the 4000 BDX minimum are rejected", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 3999,
        p_method: "Beldex",
        p_note: null,
        p_request_id: randomUUID(),
        p_currency: "BDX",
      });
      assert.ok(error, "Beldex deposit below 4000 BDX unexpectedly succeeded");
    });

    await step("USD denomination is rejected for new financial requests", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 4000,
        p_method: "Beldex",
        p_note: null,
        p_request_id: randomUUID(),
        p_currency: "USD",
      });
      assert.ok(error, "new financial request unexpectedly accepted USD denomination");
    });

    await step("non-Beldex payment methods are rejected", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 4000,
        p_method: "Bitcoin",
        p_note: null,
        p_request_id: randomUUID(),
        p_currency: "BDX",
      });
      assert.ok(error, "Bitcoin payment method unexpectedly remained enabled");
    });

    await step("financial requests reject a missing idempotency key", async () => {
      const client = await clientFor(users.normal);
      const { error } = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 4000,
        p_method: "BELDEX",
        p_note: null,
        p_request_id: null,
        p_currency: "BDX",
      });
      assert.ok(error, "financial request unexpectedly accepted a missing idempotency key");
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

    await step("BDX withdrawal lifecycle is atomic and one-way", async () => {
      const seeded = await admin.from("user_profile")
        .update({ bdx_balance: 50000, available_balance: 0 })
        .eq("user_id", users.normal.id);
      assert.ifError(seeded.error);
      const client = await clientFor(users.normal);
      const initial = await admin.from("user_profile")
        .select("bdx_balance,total_withdrawals_bdx")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(initial.error);
      const initialBalance = Number(initial.data.bdx_balance);
      const initialWithdrawals = Number(initial.data.total_withdrawals_bdx || 0);
      const address = "A".repeat(95);

      const created = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 300,
        p_method: "Beldex",
        p_note: address,
        p_request_id: randomUUID(),
        p_currency: "BDX",
      });
      assert.ifError(created.error);
      assert.ok(created.data?.id);
      assert.equal(created.data?.status, "pending");
      assert.equal(created.data?.approval_status, "awaiting");

      const afterCreate = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(afterCreate.error);
      assert.equal(Number(afterCreate.data.bdx_balance), initialBalance - 300);

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
        .select("bdx_balance,total_withdrawals_bdx")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(afterSettlement.error);
      assert.equal(Number(afterSettlement.data.bdx_balance), initialBalance - 300);
      assert.equal(Number(afterSettlement.data.total_withdrawals_bdx), initialWithdrawals + 300);

      const rejectCreated = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 300,
        p_method: "Beldex",
        p_note: address,
        p_request_id: randomUUID(),
        p_currency: "BDX",
      });
      assert.ifError(rejectCreated.error);
      assert.ok(rejectCreated.data?.id);

      const afterSecondCreate = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(afterSecondCreate.error);
      assert.equal(Number(afterSecondCreate.data.bdx_balance), initialBalance - 600);

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
        .select("bdx_balance,total_withdrawals_bdx")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(afterRejection.error);
      assert.equal(Number(afterRejection.data.bdx_balance), initialBalance - 300);
      assert.equal(Number(afterRejection.data.total_withdrawals_bdx), initialWithdrawals + 300);
    });

    await step("concurrent BDX withdrawals reserve a balance only once", async () => {
      const seeded = await admin.from("user_profile")
        .update({ bdx_balance: 50000, available_balance: 0 })
        .eq("user_id", users.normal.id);
      assert.ifError(seeded.error);
      const before = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(before.error);
      const requestIds = [randomUUID(), randomUUID()];
      const [clientA, clientB] = await Promise.all([clientFor(users.normal), clientFor(users.normal)]);
      const results = await Promise.all(requestIds.map((requestId, index) =>
        (index === 0 ? clientA : clientB).rpc("create_financial_transaction", {
          p_type: "withdraw",
          p_amount: 30000,
          p_method: "Beldex",
          p_note: "A".repeat(95),
          p_request_id: requestId,
          p_currency: "BDX",
        })
      ));
      assert.equal(results.filter((result) => !result.error).length, 1);
      assert.equal(results.filter((result) => result.error).length, 1);
      const after = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(after.error);
      assert.equal(Number(before.data.bdx_balance) - Number(after.data.bdx_balance), 30000);
      const { data, error } = await admin.from("transaction")
        .select("id")
        .eq("user_id", users.normal.id)
        .in("request_id", requestIds);
      assert.ifError(error);
      assert.equal(data?.length, 1);
    });

    await step("concurrent BDX settlement credits totals and audit once", async () => {
      const seeded = await admin.from("user_profile")
        .update({ bdx_balance: 50000, available_balance: 0 })
        .eq("user_id", users.normal.id);
      assert.ifError(seeded.error);
      const client = await clientFor(users.normal);
      const requestId = randomUUID();
      const created = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 300,
        p_method: "Beldex",
        p_note: "A".repeat(95),
        p_request_id: requestId,
        p_currency: "BDX",
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
        .select("total_withdrawals_bdx")
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
        .select("total_withdrawals_bdx")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(after.error);
      assert.equal(Number(after.data.total_withdrawals_bdx) - Number(before.data.total_withdrawals_bdx), 300);
      const { data: auditRows, error: auditError } = await admin.from("transaction_audit")
        .select("id")
        .eq("transaction_id", created.data.id)
        .eq("action", "settled");
      assert.ifError(auditError);
      assert.equal(auditRows?.length, 1);
    });

    await step("concurrent BDX withdrawals reserve BDX balance only once", async () => {
      const seeded = await admin.from("user_profile")
        .update({ bdx_balance: 5000 })
        .eq("user_id", users.normal.id);
      assert.ifError(seeded.error);
      const before = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(before.error);
      const requestIds = [randomUUID(), randomUUID()];
      const [clientA, clientB] = await Promise.all([clientFor(users.normal), clientFor(users.normal)]);
      const results = await Promise.all(requestIds.map((requestId, index) =>
        (index === 0 ? clientA : clientB).rpc("create_financial_transaction", {
          p_type: "withdraw",
          p_amount: 4000,
          p_method: "Beldex",
          p_note: "A".repeat(95),
          p_request_id: requestId,
          p_currency: "BDX",
        })
      ));
      assert.equal(results.filter((result) => !result.error).length, 1);
      assert.equal(results.filter((result) => result.error).length, 1);
      const after = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(after.error);
      assert.equal(Number(before.data.bdx_balance) - Number(after.data.bdx_balance), 4000);
      const { data, error } = await admin.from("transaction")
        .select("id")
        .eq("user_id", users.normal.id)
        .in("request_id", requestIds);
      assert.ifError(error);
      assert.equal(data?.length, 1);
    });

    await step("concurrent BDX settlement updates BDX totals and audit once", async () => {
      const seeded = await admin.from("user_profile")
        .update({ bdx_balance: 5000 })
        .eq("user_id", users.normal.id);
      assert.ifError(seeded.error);
      const client = await clientFor(users.normal);
      const requestId = randomUUID();
      const created = await client.rpc("create_financial_transaction", {
        p_type: "withdraw",
        p_amount: 4000,
        p_method: "Beldex",
        p_note: "A".repeat(95),
        p_request_id: requestId,
        p_currency: "BDX",
      });
      assert.ifError(created.error);
      const adminClientA = await clientFor(users.admin);
      const adminClientB = await clientFor(users.admin);
      const approved = await adminClientA.rpc("admin_approve_transaction", {
        p_transaction_id: created.data.id,
        p_reason: "BDX concurrency test approval",
      });
      assert.ifError(approved.error);
      const before = await admin.from("user_profile")
        .select("total_withdrawals_bdx")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(before.error);
      const results = await Promise.all([
        adminClientA.rpc("admin_settle_transaction", { p_transaction_id: created.data.id, p_reason: "concurrent BDX settlement A" }),
        adminClientB.rpc("admin_settle_transaction", { p_transaction_id: created.data.id, p_reason: "concurrent BDX settlement B" }),
      ]);
      assert.equal(results.filter((result) => !result.error).length, 1);
      assert.equal(results.filter((result) => result.error).length, 1);
      const after = await admin.from("user_profile")
        .select("total_withdrawals_bdx")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(after.error);
      assert.equal(Number(after.data.total_withdrawals_bdx) - Number(before.data.total_withdrawals_bdx), 4000);
      const { data: auditRows, error: auditError } = await admin.from("transaction_audit")
        .select("id")
        .eq("transaction_id", created.data.id)
        .eq("action", "settled");
      assert.ifError(auditError);
      assert.equal(auditRows?.length, 1);
    });

    await step("BDX admin adjustment enforces permission, idempotency, and audit integrity", async () => {
      const noPermissionClient = await clientFor(users.adminNoPermission);
      const reference = `security-bdx-adjustment-${suffix}`;
      const denied = await noPermissionClient.rpc("admin_adjust_bdx_balance", {
        p_user_id: users.normal.id,
        p_delta: 25,
        p_reason: "security regression permission test",
        p_reference: reference,
      });
      assert.ok(denied.error, "admin without approve_transactions unexpectedly adjusted a BDX balance");

      const before = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(before.error);

      const adminClient = await clientFor(users.admin);
      const args = {
        p_user_id: users.normal.id,
        p_delta: 25,
        p_reason: "security regression idempotency test",
        p_reference: reference,
      };
      const first = await adminClient.rpc("admin_adjust_bdx_balance", args);
      assert.ifError(first.error);
      assert.ok(first.data?.id, "BDX adjustment did not return a transaction row");

      const replay = await adminClient.rpc("admin_adjust_bdx_balance", args);
      assert.ifError(replay.error);
      assert.equal(replay.data?.id, first.data.id, "same reference must replay the original transaction");

      const conflictingReplay = await adminClient.rpc("admin_adjust_bdx_balance", {
        ...args,
        p_delta: 26,
      });
      assert.ok(conflictingReplay.error, "same reference unexpectedly accepted a different adjustment");

      const after = await admin.from("user_profile")
        .select("bdx_balance")
        .eq("user_id", users.normal.id)
        .single();
      assert.ifError(after.error);
      assert.equal(Number(after.data.bdx_balance) - Number(before.data.bdx_balance), 25,
        "replay or conflicting replay changed the BDX balance more than once");

      const { data: transactions, error: transactionError } = await admin.from("transaction")
        .select("id,currency,amount,method,request_id")
        .eq("id", first.data.id);
      assert.ifError(transactionError);
      assert.equal(transactions?.length, 1);
      assert.equal(transactions[0].currency, "BDX");
      assert.equal(Number(transactions[0].amount), 25);
      assert.equal(transactions[0].method, "Admin BDX adjustment");

      const { data: auditRows, error: auditError } = await admin.from("admin_action_audit")
        .select("id,action,target_id,reason,new_values")
        .eq("target_id", first.data.id)
        .eq("action", "bdx_balance_adjusted");
      assert.ifError(auditError);
      assert.equal(auditRows?.length, 1, "one matching admin audit row must exist");
      assert.equal(auditRows[0].reason, args.p_reason);
      assert.equal(auditRows[0].new_values?.currency, "BDX");
      assert.equal(auditRows[0].new_values?.reference, reference);
      assert.equal(Number(auditRows[0].new_values?.delta), 25);
    });

    await step("duplicate request_id is idempotent", async () => {
      const client = await clientFor(users.normal);
      const requestId = randomUUID();
      const first = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 4000,
        p_method: "Beldex",
        p_note: null,
        p_request_id: requestId,
        p_currency: "BDX",
      });
      assert.ifError(first.error);
      assert.ok(first.data?.id);

      const second = await client.rpc("create_financial_transaction", {
        p_type: "deposit",
        p_amount: 4000,
        p_method: "Beldex",
        p_note: null,
        p_request_id: requestId,
        p_currency: "BDX",
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
