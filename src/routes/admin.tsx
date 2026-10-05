import { createFileRoute, Navigate } from "@tanstack/react-router";
import {
  AlertTriangle,
  Ban,
  CheckCircle,
  Clock,
  Eye,
  PauseCircle,
  PlayCircle,
  RefreshCw,
  Search,
  ShieldCheck,
  TrendingUp,
  Users,
  Wallet,
  XCircle,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { AdminShell } from "@/components/admin/admin-shell";
import { supabase } from "@/lib/supabase/client";

export const Route = createFileRoute("/admin")({ component: AdminPage });

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

const money = (value: string | number) =>
  Number(value || 0).toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

const percent = (value: string | number) => `${(Number(value || 0) * 100).toFixed(2)}%`;

function AdminPage() {
  const [allowed, setAllowed] = useState<boolean | null>(null);
  const [adminRole, setAdminRole] = useState("admin");
  const [txs, setTxs] = useState<Tx[]>([]);
  const [users, setUsers] = useState<UserProfile[]>([]);
  const [investments, setInvestments] = useState<Investment[]>([]);
  const [audit, setAudit] = useState<AuditRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [tab, setTab] = useState<"dashboard" | "transactions" | "users" | "audit">("dashboard");
  const [selectedUserId, setSelectedUserId] = useState<string | null>(null);
  const [rejectId, setRejectId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState("");
  const [blockReason, setBlockReason] = useState("");
  const [rateDraft, setRateDraft] = useState("");
  const [showUserPanel, setShowUserPanel] = useState(false);

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
    else setInvestments((data ?? []) as Investment[]);
    const user = users.find((item) => item.user_id === userId);
    setBlockReason(user?.blocked_reason || "");
    setRateDraft(user && investments[0] ? String(Number(investments[0].daily_rate) * 100) : "");
  }

  useEffect(() => {
    void load();
  }, []);

  useEffect(() => {
    if (!selectedUserId) return;
    const user = users.find((item) => item.user_id === selectedUserId);
    if (user) setBlockReason(user.blocked_reason || "");
    if (investments[0]) setRateDraft(String(Number(investments[0].daily_rate) * 100));
  }, [selectedUserId, users, investments]);

  async function act(kind: "approve" | "settle" | "reject", id: string, reason?: string) {
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
      await loadTransactions();
      await loadAudit();
    }
    setBusy(null);
  }

  async function toggleBlock(user: UserProfile) {
    setBusy(`block:${user.user_id}`);
    setError("");
    const nextBlocked = !user.blocked;
    const { error: actionError } = await supabase.rpc("admin_set_user_block", {
      p_user_id: user.user_id,
      p_blocked: nextBlocked,
      p_reason: nextBlocked ? blockReason.trim() || "Blocked by administrator" : null,
    });
    if (actionError) setError(actionError.message);
    else {
      await loadUsers(query);
      await loadAudit();
    }
    setBusy(null);
  }

  async function updateInvestment(investmentId: string, dailyRatePercent?: number, enabled?: boolean) {
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
  const pendingKyc = useMemo(() => users.filter((user) => user.kyc_status === "pending").length, [users]);
  const blockedUsers = useMemo(() => users.filter((user) => user.blocked).length, [users]);
  const totalBalance = useMemo(() => users.reduce((sum, user) => sum + Number(user.available_balance || 0), 0), [users]);
  const activeInvestments = useMemo(() => investments.filter((item) => item.status === "active").length, [investments]);

  const filteredTransactions = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return txs;
    return txs.filter((tx) =>
      [tx.id, tx.user_id, tx.type, tx.method, tx.status, tx.approval_status]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(q)),
    );
  }, [txs, query]);

  const selectedUser = users.find((user) => user.user_id === selectedUserId) || null;

  if (allowed === false) return <Navigate to="/admin/login" replace />;

  return (
    <AdminShell>
      <div className="mx-auto max-w-[1500px] px-1 py-1 pb-16">
        <header className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <div className="mb-2 inline-flex items-center gap-2 rounded-full border border-accent/30 bg-accent/10 px-3 py-1 text-[11px] font-semibold uppercase tracking-wider text-accent">
              <ShieldCheck size={14} /> {adminRole}
            </div>
            <h1 className="text-2xl font-bold text-fg sm:text-3xl">Admin Control Center</h1>
            <p className="mt-1 text-sm text-muted">Manage users, transactions, investments and audit activity.</p>
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
          <div className="rounded-2xl border border-line bg-panel py-20 text-center text-muted">Loading secure admin data…</div>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
              <Stat icon={Clock} label="Awaiting approval" value={pending.length} />
              <Stat icon={CheckCircle} label="Approved / ready" value={approved.length} />
              <Stat icon={Users} label="Registered users" value={users.length} />
              <Stat icon={Ban} label="Blocked users" value={blockedUsers} />
              <Stat icon={Wallet} label="User balances" value={money(totalBalance)} />
            </div>

            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              <InfoCard label="KYC awaiting review" value={pendingKyc} />
              <InfoCard label="Automatic accrual" value="Daily at 01:00 Nigeria time" />
            </div>

            <section className="mt-6 overflow-hidden rounded-2xl border border-line bg-panel">
              <div className="flex flex-col gap-3 border-b border-line p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
                <div className="flex flex-wrap rounded-xl bg-elevated p-1">
                  {(["dashboard", "transactions", "users", "audit"] as const).map((item) => (
                    <TabButton key={item} active={tab === item} onClick={() => setTab(item)}>
                      {item === "dashboard" ? "Dashboard" : item === "audit" ? "Audit log" : item[0].toUpperCase() + item.slice(1)}
                    </TabButton>
                  ))}
                </div>
                {(tab === "transactions" || tab === "users") && (
                  <label className="flex items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 sm:min-w-[300px]">
                    <Search size={16} className="text-muted" />
                    <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={tab === "users" ? "Search email, name, username, country or ID…" : "Search transactions…"} className="min-w-0 flex-1 bg-transparent text-sm text-fg outline-none placeholder:text-muted" />
                  </label>
                )}
              </div>

              {tab === "dashboard" && (
                <div className="grid gap-4 p-4 sm:grid-cols-2 lg:grid-cols-3">
                  <ControlCard icon={Users} title="User management" text="Search accounts, inspect balances and KYC state, and block or unblock accounts." onClick={() => setTab("users")} />
                  <ControlCard icon={Wallet} title="Transaction control" text="Approve, reject and settle transactions with administrator audit records." onClick={() => setTab("transactions")} />
                  <ControlCard icon={TrendingUp} title="Investment regulation" text="Open an investor profile and regulate daily accrual settings per investment." onClick={() => setTab("users")} />
                  <ControlCard icon={ShieldCheck} title="Audit history" text="Review administrator actions and the values changed by each action." onClick={() => setTab("audit")} />
                  <ControlCard icon={RefreshCw} title="Daily accrual" text="Automatic server-side accrual runs once per day. Manual accrual is available from an investor profile." onClick={() => setTab("users")} />
                  <ControlCard icon={CheckCircle} title="KYC queue" text={`${pendingKyc} account${pendingKyc === 1 ? "" : "s"} currently awaiting KYC review.`} onClick={() => setTab("users")} />
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
                            <span className="text-lg font-semibold text-fg">{money(tx.amount)}</span>
                          </div>
                          <p className="mt-1 text-sm text-muted">{tx.method || "No method"} · {new Date(tx.created_at).toLocaleString()}</p>
                          <p className="mt-1 break-all text-xs text-subtle">User: {tx.user_id}</p>
                          {tx.note && <p className="mt-2 text-xs text-muted">{tx.note}</p>}
                        </div>
                        <div className="flex shrink-0 flex-wrap gap-2">
                          {tx.approval_status === "awaiting" && (
                            <>
                              <button type="button" disabled={busy === tx.id} onClick={() => void act("approve", tx.id)} className="inline-flex items-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60"><CheckCircle size={16} /> Approve</button>
                              <button type="button" disabled={busy === tx.id} onClick={() => { setRejectId(tx.id); setRejectReason(""); }} className="inline-flex items-center gap-2 rounded-xl border border-red-500/40 px-4 py-2.5 text-sm font-medium text-red-300 disabled:opacity-60"><XCircle size={16} /> Reject</button>
                            </>
                          )}
                          {tx.approval_status === "approved" && tx.status !== "completed" && (
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
                <div className="divide-y divide-line">
                  {users.length === 0 ? <EmptyState text="No users found." /> : users.map((user) => (
                    <div key={user.user_id} className="p-4 sm:p-5">
                      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                        <button type="button" onClick={() => void openUser(user.user_id)} className="min-w-0 text-left">
                          <div className="font-semibold text-fg">{user.fullname || user.username || "Unnamed user"}</div>
                          <div className="mt-1 break-all text-xs text-muted">{user.email || "No email"} · @{user.username || "—"} · {user.country || "Country not set"}</div>
                          <div className="mt-1 break-all text-[11px] text-subtle">{user.user_id}</div>
                        </button>
                        <div className="flex flex-wrap items-center gap-3">
                          <div><div className="text-[10px] uppercase tracking-wide text-muted">Balance</div><div className="font-semibold text-fg">{money(user.available_balance)}</div></div>
                          <Status value={user.blocked ? "blocked" : user.kyc_status || "pending"} />
                          <button type="button" onClick={() => void openUser(user.user_id)} className="inline-flex items-center gap-2 rounded-xl border border-line px-3 py-2 text-sm text-fg hover:bg-elevated"><Eye size={15} /> Manage</button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {tab === "audit" && (
                <div className="divide-y divide-line">
                  {audit.length === 0 ? <EmptyState text="No administrator actions recorded yet." /> : audit.map((row) => (
                    <div key={row.id} className="p-4 sm:p-5">
                      <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                        <div className="font-semibold text-fg">{row.action.replaceAll("_", " ")}</div>
                        <div className="text-xs text-muted">{new Date(row.created_at).toLocaleString()}</div>
                      </div>
                      <div className="mt-1 break-all text-xs text-subtle">User: {row.user_id || "—"} · Target: {row.target_id || "—"}</div>
                      {row.reason && <div className="mt-2 text-sm text-muted">{row.reason}</div>}
                    </div>
                  ))}
                </div>
              )}
            </section>
          </>
        )}

        {showUserPanel && selectedUser && (
          <div className="fixed inset-0 z-[120] flex items-end justify-center bg-black/70 p-0 sm:items-center sm:p-6" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowUserPanel(false); }}>
            <div className="max-h-[92vh] w-full max-w-4xl overflow-y-auto rounded-t-3xl border border-line bg-panel p-5 shadow-2xl sm:rounded-3xl sm:p-6">
              <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="text-xl font-bold text-fg">{selectedUser.fullname || selectedUser.username || "Unnamed user"}</h2>
                    <Status value={selectedUser.blocked ? "blocked" : selectedUser.kyc_status || "pending"} />
                  </div>
                  <p className="mt-1 break-all text-sm text-muted">{selectedUser.email || "No email"} · {selectedUser.country || "Country not set"}</p>
                  <p className="mt-1 break-all text-xs text-subtle">{selectedUser.user_id}</p>
                </div>
                <button type="button" onClick={() => setShowUserPanel(false)} className="self-end rounded-xl border border-line px-3 py-2 text-sm text-muted hover:text-fg sm:self-auto">Close</button>
              </div>

              <div className="mt-5 grid gap-3 sm:grid-cols-4">
                <MiniStat label="Available" value={money(selectedUser.available_balance)} />
                <MiniStat label="Locked" value={money(selectedUser.locked_balance)} />
                <MiniStat label="Deposits" value={money(selectedUser.total_deposits)} />
                <MiniStat label="Withdrawals" value={money(selectedUser.total_withdrawals)} />
              </div>

              <div className="mt-5 rounded-2xl border border-line bg-surface p-4">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
                  <div className="min-w-0 flex-1">
                    <label className="text-xs font-semibold uppercase tracking-wide text-muted">Block reason</label>
                    <input value={blockReason} onChange={(event) => setBlockReason(event.target.value)} maxLength={300} className="mt-2 w-full rounded-xl border border-line bg-panel px-3 py-2.5 text-sm text-fg outline-none focus:border-accent" placeholder="Reason shown in admin records" />
                  </div>
                  <button type="button" disabled={busy === `block:${selectedUser.user_id}`} onClick={() => void toggleBlock(selectedUser)} className={selectedUser.blocked ? "inline-flex items-center justify-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60" : "inline-flex items-center justify-center gap-2 rounded-xl bg-red-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60"}>
                    <Ban size={16} /> {selectedUser.blocked ? "Unblock user" : "Block user"}
                  </button>
                </div>
              </div>

              <div className="mt-5 flex items-center justify-between">
                <div><h3 className="font-semibold text-fg">Investments</h3><p className="text-xs text-muted">{activeInvestments} active investment(s) for this user</p></div>
                <button type="button" disabled={busy === `accrue:${selectedUser.user_id}`} onClick={() => void accrueNow(selectedUser.user_id)} className="inline-flex items-center gap-2 rounded-xl border border-accent/30 bg-accent/10 px-3 py-2 text-xs font-semibold text-accent disabled:opacity-60"><TrendingUp size={15} /> Accrue due now</button>
              </div>

              <div className="mt-3 space-y-3">
                {investments.length === 0 ? <EmptyState text="No investments found for this user." /> : investments.map((investment) => (
                  <div key={investment.id} className="rounded-2xl border border-line bg-surface p-4">
                    <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-semibold text-fg">{investment.plan_id || "Investment plan"}</span>
                          <Status value={investment.status} />
                          <Status value={investment.daily_accrual_enabled ? "accrual on" : "accrual off"} />
                        </div>
                        <div className="mt-2 grid gap-2 text-sm text-muted sm:grid-cols-3">
                          <span>Principal: <b className="text-fg">{money(investment.principal)}</b></span>
                          <span>Daily rate: <b className="text-fg">{percent(investment.daily_rate)}</b></span>
                          <span>Profit credited: <b className="text-fg">{money(investment.credited_profit)}</b></span>
                        </div>
                        <div className="mt-1 text-xs text-subtle">{investment.duration_days} days · Started {new Date(investment.started_at).toLocaleDateString()} · Last accrual {new Date(investment.last_accrual_at).toLocaleString()}</div>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        <input aria-label="Daily rate percent" type="number" min="0" step="0.01" value={rateDraft} onChange={(event) => setRateDraft(event.target.value)} className="w-28 rounded-xl border border-line bg-panel px-3 py-2 text-sm text-fg outline-none" />
                        <button type="button" disabled={busy === `investment:${investment.id}`} onClick={() => { const value = Number(rateDraft); if (!Number.isFinite(value) || value < 0) { setError("Enter a valid non-negative daily rate."); return; } void updateInvestment(investment.id, value); }} className="rounded-xl border border-line px-3 py-2 text-sm font-medium text-fg hover:bg-elevated disabled:opacity-60">Save rate %</button>
                        <button type="button" disabled={busy === `investment:${investment.id}`} onClick={() => void updateInvestment(investment.id, undefined, !investment.daily_accrual_enabled)} className="inline-flex items-center gap-2 rounded-xl border border-line px-3 py-2 text-sm font-medium text-fg hover:bg-elevated disabled:opacity-60">
                          {investment.daily_accrual_enabled ? <><PauseCircle size={15} /> Pause</> : <><PlayCircle size={15} /> Enable</>}
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>

              <div className="mt-5 rounded-2xl border border-line bg-surface p-4">
                <h3 className="font-semibold text-fg">Recent transactions</h3>
                <div className="mt-3 space-y-2">
                  {txs.filter((tx) => tx.user_id === selectedUser.user_id).slice(0, 20).map((tx) => (
                    <div key={tx.id} className="flex flex-col gap-1 border-b border-line pb-2 text-sm last:border-0">
                      <div className="flex justify-between gap-3"><span className="capitalize text-fg">{tx.type}</span><span className="text-fg">{money(tx.amount)}</span></div>
                      <div className="text-xs text-muted">{tx.status} · {new Date(tx.created_at).toLocaleString()}</div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </AdminShell>
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
  return <button type="button" onClick={onClick} className={active ? "rounded-lg bg-panel px-4 py-2 text-sm font-semibold text-fg shadow-sm" : "rounded-lg px-4 py-2 text-sm text-muted"}>{children}</button>;
}

function Status({ value }: { value: string }) {
  const normalized = value.toLowerCase();
  const positive = ["approved", "completed", "verified", "active", "accrual on"].includes(normalized);
  const negative = ["rejected", "failed", "blocked", "paused", "accrual off"].includes(normalized);
  return <span className={"inline-flex rounded-full border px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide " + (positive ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-300" : negative ? "border-red-500/30 bg-red-500/10 text-red-300" : "border-amber-500/30 bg-amber-500/10 text-amber-300")}>{value}</span>;
}

function EmptyState({ text }: { text: string }) {
  return <div className="p-10 text-center text-sm text-muted">{text}</div>;
}
