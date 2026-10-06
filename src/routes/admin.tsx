import { createFileRoute, Navigate } from "@tanstack/react-router";
import {
  AlertTriangle,
  Ban,
  CheckCircle,
  Clock,
  Eye,
  FileCheck2,
  PauseCircle,
  PlayCircle,
  RefreshCw,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  TrendingUp,
  Users,
  Wallet,
  XCircle,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { AdminShell } from "@/components/admin/admin-shell";
import { supabase } from "@/lib/supabase/client";

export const Route = createFileRoute("/admin")({ component: AdminPage });

type Tab = "dashboard" | "transactions" | "users" | "investments" | "kyc" | "reconciliation" | "audit" | "settings";

type Tx = {
  id: string;
  user_id: string;
  type: string;
  amount: string | number;
  status: string;
  approval_status: string;
  method: string | null;
  note: string | null;
  created_at: string;
};

type UserProfile = {
  user_id: string;
  email: string | null;
  username: string | null;
  fullname: string | null;
  phone: string | null;
  country: string | null;
  kyc_status: string | null;
  available_balance: string | number;
  locked_balance: string | number;
  total_deposits: string | number;
  total_withdrawals: string | number;
  referral_earnings: string | number;
  blocked: boolean;
  blocked_reason: string | null;
  blocked_at: string | null;
  created_at: string;
};

type Investment = {
  id: string;
  user_id: string;
  plan_id: string | null;
  principal: string | number;
  daily_rate: string | number;
  duration_days: number;
  started_at: string;
  last_accrual_at: string;
  credited_profit: string | number;
  status: string;
  completed_at: string | null;
  daily_accrual_enabled: boolean;
};

type AuditRow = {
  id: string;
  action: string;
  user_id: string | null;
  target_id: string | null;
  reason: string | null;
  old_values: Record<string, unknown> | null;
  new_values: Record<string, unknown> | null;
  created_at: string;
};

type ReconciliationRow = {
  user_id: string;
  available_balance: string | number;
  locked_balance: string | number;
  expected_locked_balance: string | number;
  locked_delta: string | number;
  total_deposits: string | number;
  recorded_deposits: string | number;
  deposits_delta: string | number;
  total_withdrawals: string | number;
  recorded_withdrawals: string | number;
  withdrawals_delta: string | number;
  referral_earnings: string | number;
  recorded_referrals: string | number;
  referral_delta: string | number;
  credited_investment_profit: string | number;
  recorded_investment_profit: string | number;
  investment_profit_delta: string | number;
  negative_balance: boolean;
};

const money = (value: string | number) =>
  Number(value || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const percent = (value: string | number) => `${(Number(value || 0) * 100).toFixed(2)}%`;
const deltaOk = (value: string | number) => Math.abs(Number(value || 0)) < 0.00000001;

function AdminPage() {
  const [allowed, setAllowed] = useState<boolean | null>(null);
  const [adminRole, setAdminRole] = useState("admin");
  const [permissions, setPermissions] = useState<string[]>([]);
  const [txs, setTxs] = useState<Tx[]>([]);
  const [users, setUsers] = useState<UserProfile[]>([]);
  const [investments, setInvestments] = useState<Investment[]>([]);
  const [audit, setAudit] = useState<AuditRow[]>([]);
  const [reconciliation, setReconciliation] = useState<ReconciliationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [reconLoading, setReconLoading] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [tab, setTab] = useState<Tab>("dashboard");
  const [selectedUserId, setSelectedUserId] = useState<string | null>(null);
  const [rejectId, setRejectId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState("");
  const [blockReason, setBlockReason] = useState("");
  const [rateDrafts, setRateDrafts] = useState<Record<string, string>>({});
  const [showUserPanel, setShowUserPanel] = useState(false);

  const hasPermission = (permission: string) =>
    permissions.length === 0 || permissions.includes("*") || permissions.includes(permission);

  const canTransactions = hasPermission("manage_transactions");
  const canUsers = hasPermission("manage_users");
  const canInvestments = hasPermission("manage_investments");
  const canAudit = hasPermission("view_audit");

  async function verifyAdmin() {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      setAllowed(false);
      return null;
    }

    const { data: admin, error: adminError } = await supabase
      .from("admin_user")
      .select("id,role,permissions")
      .eq("user_id", user.id)
      .maybeSingle();

    if (adminError || !admin) {
      setAllowed(false);
      return null;
    }

    setAllowed(true);
    setAdminRole(admin.role || "admin");
    setPermissions(Array.isArray(admin.permissions) ? admin.permissions : []);
    return user.id;
  }

  async function loadTransactions() {
    const { data, error: txError } = await supabase
      .from("transaction")
      .select("id,user_id,type,amount,status,approval_status,method,note,created_at")
      .order("created_at", { ascending: false })
      .limit(500);
    if (txError) setError(txError.message);
    else setTxs((data ?? []) as Tx[]);
  }

  async function loadUsers(search = "") {
    const { data, error: userError } = await supabase.rpc("admin_search_users", {
      p_query: search.trim(),
      p_limit: 100,
    });
    if (userError) setError(userError.message);
    else setUsers((data ?? []) as UserProfile[]);
  }

  async function loadAudit() {
    const { data, error: auditError } = await supabase
      .from("admin_action_audit")
      .select("id,action,user_id,target_id,reason,old_values,new_values,created_at")
      .order("created_at", { ascending: false })
      .limit(200);
    if (auditError) setError(auditError.message);
    else setAudit((data ?? []) as AuditRow[]);
  }

  async function loadReconciliation() {
    setReconLoading(true);
    const { data, error: reconError } = await supabase.rpc("admin_financial_reconciliation");
    if (reconError) setError(reconError.message);
    else setReconciliation((data ?? []) as ReconciliationRow[]);
    setReconLoading(false);
  }

  async function load() {
    setLoading(true);
    setError("");
    const userId = await verifyAdmin();
    if (!userId) {
      setLoading(false);
      return;
    }
    await Promise.all([loadTransactions(), loadUsers(), loadAudit()]);
    setLoading(false);
  }

  async function openUser(userId: string) {
    setSelectedUserId(userId);
    setShowUserPanel(true);
    setError("");
    const { data, error: investmentError } = await supabase
      .from("user_investment")
      .select("id,user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,credited_profit,status,completed_at,daily_accrual_enabled")
      .eq("user_id", userId)
      .order("created_at", { ascending: false });

    if (investmentError) setError(investmentError.message);
    else {
      const freshInvestments = (data ?? []) as Investment[];
      setInvestments(freshInvestments);
      setRateDrafts((current) => {
        const next = { ...current };
        for (const investment of freshInvestments) {
          next[investment.id] = String(Number(investment.daily_rate) * 100);
        }
        return next;
      });
    }

    const user = users.find((item) => item.user_id === userId);
    setBlockReason(user?.blocked_reason || "");
  }

  useEffect(() => {
    void load();
  }, []);

  async function act(kind: "approve" | "settle" | "reject", id: string, reason?: string) {
    if (!canTransactions) return;
    setBusy(id);
    setError("");
    const rpc =
      kind === "approve"
        ? "admin_approve_transaction"
        : kind === "reject"
          ? "admin_reject_transaction"
          : "admin_settle_transaction";

    const { error: actionError } = await supabase.rpc(rpc, {
      p_transaction_id: id,
      p_reason: kind === "reject" ? reason || "Rejected by administrator" : reason || null,
    });

    if (actionError) setError(actionError.message);
    else {
      setRejectId(null);
      setRejectReason("");
      await Promise.all([loadTransactions(), loadAudit()]);
    }
    setBusy(null);
  }

  async function toggleBlock(user: UserProfile) {
    if (!canUsers) return;
    setBusy(`block:${user.user_id}`);
    setError("");
    const nextBlocked = !user.blocked;
    const { error: actionError } = await supabase.rpc("admin_set_user_block", {
      p_user_id: user.user_id,
      p_blocked: nextBlocked,
      p_reason: nextBlocked ? blockReason.trim() || "Blocked by administrator" : null,
    });
    if (actionError) setError(actionError.message);
    else await Promise.all([loadUsers(query), loadAudit()]);
    setBusy(null);
  }

  async function updateInvestment(investmentId: string, dailyRatePercent?: number, enabled?: boolean) {
    if (!canInvestments) return;
    setBusy(`investment:${investmentId}`);
    setError("");
    const payload: { p_investment_id: string; p_daily_rate?: number; p_daily_accrual_enabled?: boolean } = {
      p_investment_id: investmentId,
    };
    if (dailyRatePercent !== undefined) payload.p_daily_rate = dailyRatePercent / 100;
    if (enabled !== undefined) payload.p_daily_accrual_enabled = enabled;

    const { error: actionError } = await supabase.rpc("admin_update_investment", payload);
    if (actionError) setError(actionError.message);
    else {
      if (selectedUserId) await openUser(selectedUserId);
      await loadAudit();
    }
    setBusy(null);
  }

  async function accrueNow(userId: string) {
    if (!canInvestments) return;
    setBusy(`accrue:${userId}`);
    setError("");
    const { error: actionError } = await supabase.rpc("accrue_user_investments", { p_user_id: userId });
    if (actionError) setError(actionError.message);
    else {
      await Promise.all([loadUsers(query), loadTransactions(), loadAudit()]);
      if (selectedUserId) await openUser(selectedUserId);
    }
    setBusy(null);
  }

  const pending = useMemo(() => txs.filter((tx) => tx.approval_status === "awaiting"), [txs]);
  const approved = useMemo(() => txs.filter((tx) => tx.approval_status === "approved"), [txs]);
  const pendingKyc = useMemo(() => users.filter((user) => user.kyc_status === "pending"), [users]);
  const blockedUsers = useMemo(() => users.filter((user) => user.blocked).length, [users]);
  const totalBalance = useMemo(() => users.reduce((sum, user) => sum + Number(user.available_balance || 0), 0), [users]);
  const activeInvestments = useMemo(() => investments.filter((item) => item.status === "active").length, [investments]);
  const reconciliationProblems = useMemo(
    () =>
      reconciliation.filter(
        (row) =>
          row.negative_balance ||
          !deltaOk(row.locked_delta) ||
          !deltaOk(row.deposits_delta) ||
          !deltaOk(row.withdrawals_delta) ||
          !deltaOk(row.referral_delta) ||
          !deltaOk(row.investment_profit_delta),
      ),
    [reconciliation],
  );

  const filteredTransactions = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return txs;
    return txs.filter((tx) =>
      [tx.id, tx.user_id, tx.type, tx.method, tx.status, tx.approval_status, tx.note]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(q)),
    );
  }, [txs, query]);

  const filteredUsers = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return users;
    return users.filter((user) =>
      [user.user_id, user.email, user.username, user.fullname, user.country, user.kyc_status]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(q)),
    );
  }, [users, query]);

  const selectedUser = users.find((user) => user.user_id === selectedUserId) || null;

  const setSection = (next: Tab) => {
    setTab(next);
    setQuery("");
    if (next === "reconciliation") void loadReconciliation();
  };

  if (allowed === false) return <Navigate to="/admin/login" replace />;

  return (
    <AdminShell activeSection={tab} onSectionChange={setSection}>
      <div className="mx-auto max-w-[1500px] px-1 py-1 pb-16">
        <header className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <div className="mb-2 inline-flex items-center gap-2 rounded-full border border-accent/30 bg-accent/10 px-3 py-1 text-[11px] font-semibold uppercase tracking-wider text-accent">
              <ShieldCheck size={14} /> {adminRole}
            </div>
            <h1 className="text-2xl font-bold text-fg sm:text-3xl">Admin Operations Console</h1>
            <p className="mt-1 text-sm text-muted">Monitor operations, review exceptions, and execute protected administrator workflows.</p>
          </div>
          <button type="button" onClick={() => void load()} disabled={loading} className="inline-flex items-center justify-center gap-2 rounded-xl border border-line bg-panel px-4 py-2.5 text-sm font-medium text-fg hover:bg-elevated disabled:opacity-60">
            <RefreshCw size={16} className={loading ? "animate-spin" : ""} /> Refresh
          </button>
        </header>

        {error && (
          <div className="mb-5 flex gap-3 rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-300">
            <AlertTriangle size={18} className="mt-0.5 shrink-0" /><span>{error}</span>
          </div>
        )}

        {loading ? (
          <div className="rounded-2xl border border-line bg-panel py-20 text-center text-muted">Loading secure operations data…</div>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
              <Stat icon={Clock} label="Awaiting approval" value={pending.length} />
              <Stat icon={CheckCircle} label="Approved / ready" value={approved.length} />
              <Stat icon={Users} label="Registered users" value={users.length} />
              <Stat icon={Ban} label="Blocked users" value={blockedUsers} />
              <Stat icon={Wallet} label="User balances" value={money(totalBalance)} />
              <Stat icon={FileCheck2} label="KYC queue" value={pendingKyc.length} />
            </div>

            <div className="mt-3 grid gap-3 sm:grid-cols-3">
              <InfoCard label="Automatic accrual" value="Daily at 01:00 Nigeria time" />
              <InfoCard label="Reconciliation" value={reconciliation.length ? (reconciliationProblems.length ? `${reconciliationProblems.length} exception(s)` : "No exceptions") : "Run a check"} />
              <InfoCard label="Financial writes" value="Protected server-side RPCs only" />
            </div>

            <section className="mt-6 overflow-hidden rounded-2xl border border-line bg-panel">
              <div className="flex flex-col gap-3 border-b border-line p-4 sm:p-5">
                <div className="flex flex-wrap gap-1 rounded-xl bg-elevated p-1">
                  {([
                    ["dashboard", "Dashboard"],
                    ["transactions", "Transactions"],
                    ["users", "Users"],
                    ["investments", "Investments"],
                    ["kyc", "KYC"],
                    ["reconciliation", "Reconciliation"],
                    ["audit", "Audit log"],
                    ["settings", "Operations"],
                  ] as [Tab, string][]).map(([item, label]) => (
                    <TabButton key={item} active={tab === item} onClick={() => setSection(item)}>{label}</TabButton>
                  ))}
                </div>
                {(tab === "transactions" || tab === "users" || tab === "kyc" || tab === "investments") && (
                  <label className="flex items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 sm:max-w-xl">
                    <Search size={16} className="text-muted" />
                    <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={tab === "transactions" ? "Search transaction ID, user, type, method or status…" : "Search email, name, username, country, KYC status or ID…"} className="min-w-0 flex-1 bg-transparent text-sm text-fg outline-none placeholder:text-muted" />
                  </label>
                )}
              </div>

              {tab === "dashboard" && (
                <div className="grid gap-4 p-4 sm:grid-cols-2 lg:grid-cols-3">
                  <ControlCard icon={Users} title="Users & access" text="Search accounts, inspect balances and manage blocks through protected RPCs." onClick={() => setSection("users")} />
                  <ControlCard icon={Wallet} title="Transaction operations" text="Approve, reject and settle transactions with server-side authorization and audit trails." onClick={() => setSection("transactions")} />
                  <ControlCard icon={TrendingUp} title="Investment operations" text="Review active plans, regulate accrual settings and run due accrual through protected RPCs." onClick={() => setSection("investments")} />
                  <ControlCard icon={FileCheck2} title="KYC review queue" text={`${pendingKyc.length} account${pendingKyc.length === 1 ? "" : "s"} currently awaiting review. KYC mutation controls are intentionally disabled until a dedicated protected RPC exists.`} onClick={() => setSection("kyc")} />
                  <ControlCard icon={ShieldCheck} title="Financial reconciliation" text="Run a read-only server-side reconciliation across balances, investments and transaction totals." onClick={() => setSection("reconciliation")} />
                  <ControlCard icon={SlidersHorizontal} title="Operations & safeguards" text="Review scheduler state, permissions and the boundaries of the administrator console." onClick={() => setSection("settings")} />
                </div>
              )}

              {tab === "transactions" && (
                <div className="divide-y divide-line">
                  {filteredTransactions.length === 0 ? <EmptyState text="No transactions found." /> : filteredTransactions.map((tx) => (
                    <div key={tx.id} className="p-4 sm:p-5">
                      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="font-semibold capitalize text-fg">{tx.type}</span>
                            <Status value={tx.approval_status} />
                            <Status value={tx.status} />
                            <span className="text-lg font-semibold text-fg">{money(tx.amount)}</span>
                          </div>
                          <p className="mt-1 text-sm text-muted">{tx.method || "No method"} · {new Date(tx.created_at).toLocaleString()}</p>
                          <p className="mt-1 break-all text-xs text-subtle">User: {tx.user_id} · Transaction: {tx.id}</p>
                          {tx.note && <p className="mt-2 text-xs text-muted">{tx.note}</p>}
                        </div>
                        <div className="flex shrink-0 flex-wrap gap-2">
                          {canTransactions && tx.approval_status === "awaiting" && (
                            <>
                              <button type="button" disabled={busy === tx.id} onClick={() => void act("approve", tx.id)} className="inline-flex items-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60"><CheckCircle size={16} /> Approve</button>
                              <button type="button" disabled={busy === tx.id} onClick={() => { setRejectId(tx.id); setRejectReason(""); }} className="inline-flex items-center gap-2 rounded-xl border border-red-500/40 px-4 py-2.5 text-sm font-medium text-red-300 disabled:opacity-60"><XCircle size={16} /> Reject</button>
                            </>
                          )}
                          {canTransactions && tx.approval_status === "approved" && tx.status !== "completed" && (
                            <button type="button" disabled={busy === tx.id} onClick={() => void act("settle", tx.id)} className="inline-flex items-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60"><CheckCircle size={16} /> Settle</button>
                          )}
                        </div>
                      </div>
                      {rejectId === tx.id && (
                        <div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/5 p-4">
                          <label className="block text-xs font-semibold uppercase tracking-wide text-muted">Rejection reason</label>
                          <textarea value={rejectReason} onChange={(event) => setRejectReason(event.target.value)} rows={3} maxLength={500} placeholder="Explain why this transaction is being rejected…" className="mt-2 w-full rounded-xl border border-line bg-surface p-3 text-sm text-fg outline-none focus:border-accent" />
                          <div className="mt-3 flex gap-2">
                            <button type="button" disabled={busy === tx.id || !rejectReason.trim()} onClick={() => void act("reject", tx.id, rejectReason.trim())} className="rounded-xl bg-red-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">Confirm rejection</button>
                            <button type="button" onClick={() => setRejectId(null)} className="rounded-xl border border-line px-4 py-2 text-sm">Cancel</button>
                          </div>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}

              {tab === "users" && (
                <UserList users={filteredUsers} onOpen={(id) => void openUser(id)} />
              )}

              {tab === "investments" && (
                <InvestmentQueue users={filteredUsers} onOpen={(id) => void openUser(id)} />
              )}

              {tab === "kyc" && (
                <KycQueue users={pendingKyc.filter((user) => {
                  const q = query.trim().toLowerCase();
                  return !q || [user.user_id, user.email, user.username, user.fullname, user.country].filter(Boolean).some((value) => String(value).toLowerCase().includes(q));
                })} onOpen={(id) => void openUser(id)} />
              )}

              {tab === "reconciliation" && (
                <ReconciliationPanel rows={reconciliation} loading={reconLoading} problems={reconciliationProblems.length} onRun={() => void loadReconciliation()} />
              )}

              {tab === "audit" && (
                <div className="divide-y divide-line">
                  {!canAudit ? (
                    <EmptyState text="Your administrator role does not include audit-log access." />
                  ) : audit.length === 0 ? <EmptyState text="No administrator actions recorded yet." /> : audit.map((row) => (
                    <div key={row.id} className="p-4 sm:p-5">
                      <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                        <div className="font-semibold capitalize text-fg">{row.action.replaceAll("_", " ")}</div>
                        <div className="text-xs text-muted">{new Date(row.created_at).toLocaleString()}</div>
                      </div>
                      <div className="mt-1 break-all text-xs text-subtle">User: {row.user_id || "—"} · Target: {row.target_id || "—"}</div>
                      {row.reason && <div className="mt-2 text-sm text-muted">{row.reason}</div>}
                    </div>
                  ))}
                </div>
              )}

              {tab === "settings" && (
                <OperationsPanel adminRole={adminRole} permissions={permissions} canTransactions={canTransactions} canUsers={canUsers} canInvestments={canInvestments} canAudit={canAudit} />
              )}
            </section>
          </>
        )}

        {showUserPanel && selectedUser && (
          <UserModal
            user={selectedUser}
            investments={investments}
            txs={txs.filter((tx) => tx.user_id === selectedUser.user_id).slice(0, 20)}
            canUsers={canUsers}
            canInvestments={canInvestments}
            busy={busy}
            blockReason={blockReason}
            setBlockReason={setBlockReason}
            rateDrafts={rateDrafts}
            setRateDrafts={setRateDrafts}
            onClose={() => setShowUserPanel(false)}
            onBlock={() => void toggleBlock(selectedUser)}
            onAccrue={() => void accrueNow(selectedUser.user_id)}
            onUpdateInvestment={updateInvestment}
          />
        )}
      </div>
    </AdminShell>
  );
}

function UserList({ users, onOpen }: { users: UserProfile[]; onOpen: (id: string) => void }) {
  return (
    <div className="divide-y divide-line">
      {users.length === 0 ? <EmptyState text="No users found." /> : users.map((user) => (
        <div key={user.user_id} className="p-4 sm:p-5">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <button type="button" onClick={() => onOpen(user.user_id)} className="min-w-0 text-left">
              <div className="font-semibold text-fg">{user.fullname || user.username || "Unnamed user"}</div>
              <div className="mt-1 break-all text-xs text-muted">{user.email || "No email"} · @{user.username || "—"} · {user.country || "Country not set"}</div>
              <div className="mt-1 break-all text-[11px] text-subtle">{user.user_id}</div>
            </button>
            <div className="flex flex-wrap items-center gap-3">
              <div><div className="text-[10px] uppercase tracking-wide text-muted">Balance</div><div className="font-semibold text-fg">{money(user.available_balance)}</div></div>
              <Status value={user.blocked ? "blocked" : user.kyc_status || "pending"} />
              <button type="button" onClick={() => onOpen(user.user_id)} className="inline-flex items-center gap-2 rounded-xl border border-line px-3 py-2 text-sm text-fg hover:bg-elevated"><Eye size={15} /> Manage</button>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

function InvestmentQueue({ users, onOpen }: { users: UserProfile[]; onOpen: (id: string) => void }) {
  return (
    <div className="divide-y divide-line">
      {users.length === 0 ? <EmptyState text="No users found. Open a user to inspect investment operations." /> : users.map((user) => (
        <div key={user.user_id} className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <div>
            <div className="font-semibold text-fg">{user.fullname || user.username || "Unnamed user"}</div>
            <div className="mt-1 text-xs text-muted">{user.email || "No email"} · Locked {money(user.locked_balance)} · Available {money(user.available_balance)}</div>
          </div>
          <button type="button" onClick={() => onOpen(user.user_id)} className="inline-flex items-center justify-center gap-2 rounded-xl border border-line px-3 py-2 text-sm text-fg hover:bg-elevated"><TrendingUp size={15} /> Open investments</button>
        </div>
      ))}
    </div>
  );
}

function KycQueue({ users, onOpen }: { users: UserProfile[]; onOpen: (id: string) => void }) {
  return (
    <div className="divide-y divide-line">
      {users.length === 0 ? <EmptyState text="No pending KYC profiles in the loaded queue." /> : users.map((user) => (
        <div key={user.user_id} className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
          <div>
            <div className="flex flex-wrap items-center gap-2"><span className="font-semibold text-fg">{user.fullname || user.username || "Unnamed user"}</span><Status value={user.kyc_status || "pending"} /></div>
            <div className="mt-1 text-xs text-muted">{user.email || "No email"} · {user.country || "Country not set"}</div>
            <div className="mt-1 text-xs text-subtle">Created {new Date(user.created_at).toLocaleDateString()}</div>
          </div>
          <button type="button" onClick={() => onOpen(user.user_id)} className="inline-flex items-center justify-center gap-2 rounded-xl border border-line px-3 py-2 text-sm text-fg hover:bg-elevated"><Eye size={15} /> Review profile</button>
        </div>
      ))}
      <div className="m-4 rounded-xl border border-amber-500/20 bg-amber-500/5 p-4 text-xs leading-5 text-amber-200">KYC approval/rejection is intentionally read-only here. No dedicated protected KYC mutation RPC was found in the current backend, so the console will not write KYC state directly.</div>
    </div>
  );
}

function ReconciliationPanel({ rows, loading, problems, onRun }: { rows: ReconciliationRow[]; loading: boolean; problems: number; onRun: () => void }) {
  return (
    <div className="p-4 sm:p-5">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div><h2 className="font-semibold text-fg">Read-only financial reconciliation</h2><p className="mt-1 text-xs text-muted">Server-side comparison of profile balances, active investment principal and completed transaction totals.</p></div>
        <button type="button" onClick={onRun} disabled={loading} className="inline-flex items-center justify-center gap-2 rounded-xl border border-line px-3 py-2 text-sm text-fg hover:bg-elevated disabled:opacity-60"><RefreshCw size={15} className={loading ? "animate-spin" : ""} /> Run check</button>
      </div>
      {rows.length === 0 ? <EmptyState text="Run reconciliation to load the current server-side checks." /> : (
        <>
          <div className={`mt-4 rounded-xl border p-4 ${problems ? "border-red-500/30 bg-red-500/5 text-red-200" : "border-emerald-500/30 bg-emerald-500/5 text-emerald-200"}`}>
            <div className="font-semibold">{problems ? `${problems} account(s) need review` : "All loaded accounts reconcile"}</div>
            <div className="mt-1 text-xs opacity-80">{problems ? "No automatic repair was attempted." : "All tested deltas are zero and no negative balances were reported."}</div>
          </div>
          <div className="mt-4 overflow-x-auto rounded-xl border border-line">
            <table className="min-w-[980px] w-full text-left text-xs">
              <thead className="bg-elevated text-muted"><tr><th className="p-3">User</th><th className="p-3">Available</th><th className="p-3">Locked Δ</th><th className="p-3">Deposits Δ</th><th className="p-3">Withdrawals Δ</th><th className="p-3">Referrals Δ</th><th className="p-3">Profit Δ</th><th className="p-3">Status</th></tr></thead>
              <tbody className="divide-y divide-line">{rows.map((row) => {
                const bad = row.negative_balance || !deltaOk(row.locked_delta) || !deltaOk(row.deposits_delta) || !deltaOk(row.withdrawals_delta) || !deltaOk(row.referral_delta) || !deltaOk(row.investment_profit_delta);
                return <tr key={row.user_id}><td className="p-3 font-mono text-[10px]">{row.user_id}</td><td className="p-3">{money(row.available_balance)}</td><td className="p-3">{money(row.locked_delta)}</td><td className="p-3">{money(row.deposits_delta)}</td><td className="p-3">{money(row.withdrawals_delta)}</td><td className="p-3">{money(row.referral_delta)}</td><td className="p-3">{money(row.investment_profit_delta)}</td><td className="p-3"><Status value={bad ? "review" : "ok"} /></td></tr>;
              })}</tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}

function OperationsPanel({ adminRole, permissions, canTransactions, canUsers, canInvestments, canAudit }: { adminRole: string; permissions: string[]; canTransactions: boolean; canUsers: boolean; canInvestments: boolean; canAudit: boolean }) {
  return (
    <div className="grid gap-4 p-4 sm:grid-cols-2 sm:p-5">
      <InfoCard label="Administrator role" value={adminRole} />
      <InfoCard label="Permission mode" value={permissions.length ? permissions.join(", ") : "Legacy/full administrator"} />
      <InfoCard label="Transaction mutations" value={canTransactions ? "Enabled through protected RPCs" : "UI disabled"} />
      <InfoCard label="User mutations" value={canUsers ? "Enabled through protected RPCs" : "UI disabled"} />
      <InfoCard label="Investment mutations" value={canInvestments ? "Enabled through protected RPCs" : "UI disabled"} />
      <InfoCard label="Audit access" value={canAudit ? "Enabled" : "UI disabled"} />
      <div className="sm:col-span-2 rounded-2xl border border-line bg-surface p-5">
        <div className="flex items-center gap-2 font-semibold text-fg"><ShieldCheck size={18} className="text-accent" /> Financial safety boundary</div>
        <p className="mt-2 text-sm leading-6 text-muted">This console never writes balances, investments or transaction states directly. Approvals, rejections, settlements, blocks, investment regulation and accrual all remain behind server-side authorization and database RPCs.</p>
      </div>
      <div className="sm:col-span-2 rounded-2xl border border-amber-500/20 bg-amber-500/5 p-5">
        <div className="font-semibold text-amber-200">Emergency financial pause</div>
        <p className="mt-2 text-sm leading-6 text-amber-100/80">No client-side emergency switch has been added because a safe circuit breaker must be enforced by the backend RPC layer itself. The UI will not pretend a local toggle can stop financial writes.</p>
      </div>
      <div className="sm:col-span-2 rounded-2xl border border-line bg-surface p-5">
        <div className="flex items-center gap-2 font-semibold text-fg"><Clock size={18} className="text-accent" /> Automated accrual</div>
        <p className="mt-2 text-sm leading-6 text-muted">Production daily accrual is scheduled server-side at 00:00 UTC (01:00 Nigeria time during WAT). Manual accrual from a user profile also remains protected by the investment authorization path.</p>
      </div>
    </div>
  );
}

function UserModal({ user, investments, txs, canUsers, canInvestments, busy, blockReason, setBlockReason, rateDrafts, setRateDrafts, onClose, onBlock, onAccrue, onUpdateInvestment }: {
  user: UserProfile;
  investments: Investment[];
  txs: Tx[];
  canUsers: boolean;
  canInvestments: boolean;
  busy: string | null;
  blockReason: string;
  setBlockReason: (value: string) => void;
  rateDrafts: Record<string, string>;
  setRateDrafts: React.Dispatch<React.SetStateAction<Record<string, string>>>;
  onClose: () => void;
  onBlock: () => void;
  onAccrue: () => void;
  onUpdateInvestment: (investmentId: string, dailyRatePercent?: number, enabled?: boolean) => Promise<void>;
}) {
  const activeInvestments = investments.filter((item) => item.status === "active").length;

  return (
    <div className="fixed inset-0 z-[120] flex items-end justify-center bg-black/70 p-0 sm:items-center sm:p-6" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <div className="max-h-[92vh] w-full max-w-5xl overflow-y-auto rounded-t-3xl border border-line bg-panel p-5 shadow-2xl sm:rounded-3xl sm:p-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div><div className="flex flex-wrap items-center gap-2"><h2 className="text-xl font-bold text-fg">{user.fullname || user.username || "Unnamed user"}</h2><Status value={user.blocked ? "blocked" : user.kyc_status || "pending"} /></div><p className="mt-1 break-all text-sm text-muted">{user.email || "No email"} · {user.country || "Country not set"}</p><p className="mt-1 break-all text-xs text-subtle">{user.user_id}</p></div>
          <button type="button" onClick={onClose} className="self-end rounded-xl border border-line px-3 py-2 text-sm text-muted hover:text-fg sm:self-auto">Close</button>
        </div>

        <div className="mt-5 grid gap-3 sm:grid-cols-4">
          <MiniStat label="Available" value={money(user.available_balance)} />
          <MiniStat label="Locked" value={money(user.locked_balance)} />
          <MiniStat label="Deposits" value={money(user.total_deposits)} />
          <MiniStat label="Withdrawals" value={money(user.total_withdrawals)} />
        </div>

        <div className="mt-5 rounded-2xl border border-line bg-surface p-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div className="min-w-0 flex-1"><label className="text-xs font-semibold uppercase tracking-wide text-muted">Block reason</label><input value={blockReason} onChange={(event) => setBlockReason(event.target.value)} maxLength={300} disabled={!canUsers} className="mt-2 w-full rounded-xl border border-line bg-panel px-3 py-2.5 text-sm text-fg outline-none focus:border-accent disabled:opacity-60" placeholder="Reason shown in admin records" /></div>
            <button type="button" disabled={!canUsers || busy === `block:${user.user_id}`} onClick={onBlock} className={user.blocked ? "inline-flex items-center justify-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60" : "inline-flex items-center justify-center gap-2 rounded-xl bg-red-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60"}><Ban size={16} /> {user.blocked ? "Unblock user" : "Block user"}</button>
          </div>
        </div>

        <div className="mt-5 flex items-center justify-between">
          <div><h3 className="font-semibold text-fg">Investment operations</h3><p className="text-xs text-muted">{activeInvestments} active investment(s)</p></div>
          <button type="button" disabled={!canInvestments || busy === `accrue:${user.user_id}`} onClick={onAccrue} className="inline-flex items-center gap-2 rounded-xl border border-accent/30 bg-accent/10 px-3 py-2 text-xs font-semibold text-accent disabled:opacity-60"><TrendingUp size={15} /> Accrue due now</button>
        </div>

        <div className="mt-3 space-y-3">
          {investments.length === 0 ? <EmptyState text="No investments found for this user." /> : investments.map((investment) => (
            <div key={investment.id} className="rounded-2xl border border-line bg-surface p-4">
              <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                <div><div className="flex flex-wrap items-center gap-2"><span className="font-semibold text-fg">{investment.plan_id || "Investment plan"}</span><Status value={investment.status} /><Status value={investment.daily_accrual_enabled ? "accrual on" : "accrual off"} /></div><div className="mt-2 grid gap-2 text-sm text-muted sm:grid-cols-3"><span>Principal: <b className="text-fg">{money(investment.principal)}</b></span><span>Daily rate: <b className="text-fg">{percent(investment.daily_rate)}</b></span><span>Profit credited: <b className="text-fg">{money(investment.credited_profit)}</b></span></div><div className="mt-1 text-xs text-subtle">{investment.duration_days} days · Started {new Date(investment.started_at).toLocaleDateString()} · Last accrual {new Date(investment.last_accrual_at).toLocaleString()}</div></div>
                <div className="flex flex-wrap gap-2">
                  <input aria-label="Daily rate percent" type="number" min="0" step="0.01" value={rateDrafts[investment.id] ?? String(Number(investment.daily_rate) * 100)} onChange={(event) => setRateDrafts((current) => ({ ...current, [investment.id]: event.target.value }))} disabled={!canInvestments} className="w-28 rounded-xl border border-line bg-panel px-3 py-2 text-sm text-fg outline-none disabled:opacity-60" />
                  <button type="button" disabled={!canInvestments || busy === `investment:${investment.id}`} onClick={() => { const value = Number(rateDrafts[investment.id]); if (!Number.isFinite(value) || value < 0) return; void onUpdateInvestment(investment.id, value); }} className="rounded-xl border border-line px-3 py-2 text-sm font-medium text-fg hover:bg-elevated disabled:opacity-60">Save rate %</button>
                  <button type="button" disabled={!canInvestments || busy === `investment:${investment.id}`} onClick={() => void onUpdateInvestment(investment.id, undefined, !investment.daily_accrual_enabled)} className="inline-flex items-center gap-2 rounded-xl border border-line px-3 py-2 text-sm font-medium text-fg hover:bg-elevated disabled:opacity-60">{investment.daily_accrual_enabled ? <><PauseCircle size={15} /> Pause</> : <><PlayCircle size={15} /> Enable</>}</button>
                </div>
              </div>
            </div>
          ))}
        </div>

        <div className="mt-5 rounded-2xl border border-line bg-surface p-4">
          <h3 className="font-semibold text-fg">Recent transactions</h3>
          <div className="mt-3 space-y-2">{txs.length ? txs.map((tx) => <div key={tx.id} className="flex flex-col gap-1 border-b border-line pb-2 text-sm last:border-0"><div className="flex justify-between gap-3"><span className="capitalize text-fg">{tx.type}</span><span className="text-fg">{money(tx.amount)}</span></div><div className="text-xs text-muted">{tx.status} · {new Date(tx.created_at).toLocaleString()}</div></div>) : <EmptyState text="No recent transactions loaded." />}</div>
        </div>
      </div>
    </div>
  );
}

function Stat({ icon: Icon, label, value }: { icon: typeof Clock; label: string; value: string | number }) {
  return <div className="rounded-2xl border border-line bg-panel p-4 sm:p-5"><div className="flex items-center gap-2 text-xs font-medium text-muted"><Icon size={16} /> {label}</div><div className="mt-2 text-2xl font-bold text-fg">{value}</div></div>;
}

function MiniStat({ label, value }: { label: string; value: string | number }) {
  return <div className="rounded-xl border border-line bg-surface p-3"><div className="text-[10px] uppercase tracking-wide text-muted">{label}</div><div className="mt-1 font-semibold text-fg">{value}</div></div>;
}

function InfoCard({ label, value }: { label: string; value: string | number }) {
  return <div className="rounded-xl border border-line bg-panel px-4 py-3 text-sm text-muted"><span className="font-medium text-fg">{label}:</span> {value}</div>;
}

function ControlCard({ icon: Icon, title, text, onClick }: { icon: typeof Users; title: string; text: string; onClick: () => void }) {
  return <button type="button" onClick={onClick} className="rounded-2xl border border-line bg-surface p-5 text-left transition hover:border-accent/30 hover:bg-elevated"><Icon size={20} className="text-accent" /><div className="mt-3 font-semibold text-fg">{title}</div><p className="mt-1 text-sm leading-6 text-muted">{text}</p></button>;
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return <button type="button" onClick={onClick} className={active ? "rounded-lg bg-panel px-4 py-2 text-sm font-semibold text-fg shadow-sm" : "rounded-lg px-4 py-2 text-sm text-muted hover:text-fg"}>{children}</button>;
}

function Status({ value }: { value: string }) {
  const normalized = value.toLowerCase();
  const positive = ["approved", "completed", "verified", "active", "accrual on", "ok"].includes(normalized);
  const negative = ["rejected", "failed", "blocked", "paused", "accrual off", "review"].includes(normalized);
  return <span className={"inline-flex rounded-full border px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide " + (positive ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-300" : negative ? "border-red-500/30 bg-red-500/10 text-red-300" : "border-amber-500/30 bg-amber-500/10 text-amber-300")}>{value}</span>;
}

function EmptyState({ text }: { text: string }) {
  return <div className="p-10 text-center text-sm text-muted">{text}</div>;
}
