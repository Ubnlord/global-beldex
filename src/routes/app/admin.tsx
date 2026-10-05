import { createFileRoute, Navigate } from "@tanstack/react-router";
import {
  AlertTriangle,
  CheckCircle,
  Clock,
  RefreshCw,
  Search,
  ShieldCheck,
  Users,
  Wallet,
  XCircle,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";

export const Route = createFileRoute("/app/admin")({ component: AdminPage });

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
  id: string;
  user_id: string;
  username: string | null;
  fullname: string | null;
  country: string | null;
  kyc_status: string | null;
  available_balance: string | number;
  total_deposits: string | number;
  total_withdrawals: string | number;
};

const money = (value: string | number) =>
  Number(value || 0).toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

function AdminPage() {
  const [allowed, setAllowed] = useState<boolean | null>(null);
  const [adminRole, setAdminRole] = useState<string>("");
  const [txs, setTxs] = useState<Tx[]>([]);
  const [users, setUsers] = useState<UserProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [tab, setTab] = useState<"transactions" | "users">("transactions");
  const [rejectId, setRejectId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState("");

  async function load() {
    setLoading(true);
    setError("");

    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      setAllowed(false);
      setLoading(false);
      return;
    }

    const { data: admin, error: adminError } = await supabase
      .from("admin_user")
      .select("id,role,permissions")
      .eq("user_id", user.id)
      .maybeSingle();

    if (adminError || !admin) {
      setAllowed(false);
      setLoading(false);
      return;
    }

    setAllowed(true);
    setAdminRole(admin.role || "admin");

    const [transactions, profiles] = await Promise.all([
      supabase
        .from("transaction")
        .select("id,user_id,type,amount,status,approval_status,method,note,created_at")
        .order("created_at", { ascending: false })
        .limit(200),
      supabase
        .from("user_profile")
        .select(
          "id,user_id,username,fullname,country,kyc_status,available_balance,total_deposits,total_withdrawals",
        )
        .order("created_at", { ascending: false })
        .limit(500),
    ]);

    if (transactions.error) setError(transactions.error.message);
    else setTxs((transactions.data ?? []) as Tx[]);

    if (profiles.error && !transactions.error) setError(profiles.error.message);
    else setUsers((profiles.data ?? []) as UserProfile[]);

    setLoading(false);
  }

  useEffect(() => {
    void load();
  }, []);

  async function act(
    kind: "approve" | "settle" | "reject",
    id: string,
    reason?: string,
  ) {
    setBusy(id);
    setError("");

    const rpc =
      kind === "approve"
        ? "admin_approve_transaction"
        : kind === "reject"
          ? "admin_reject_transaction"
          : "admin_settle_transaction";

    const args = {
      p_transaction_id: id,
      p_reason:
        kind === "reject"
          ? reason || "Rejected by administrator"
          : reason || null,
    };

    const { error: actionError } = await supabase.rpc(rpc, args);

    if (actionError) {
      setError(actionError.message);
    } else {
      setRejectId(null);
      setRejectReason("");
      await load();
    }

    setBusy(null);
  }

  const pending = useMemo(
    () => txs.filter((tx) => tx.approval_status === "awaiting"),
    [txs],
  );
  const approved = useMemo(
    () => txs.filter((tx) => tx.approval_status === "approved"),
    [txs],
  );
  const pendingKyc = useMemo(
    () => users.filter((user) => user.kyc_status === "pending").length,
    [users],
  );
  const totalBalance = useMemo(
    () => users.reduce((sum, user) => sum + Number(user.available_balance || 0), 0),
    [users],
  );

  const filteredTransactions = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return txs;
    return txs.filter((tx) =>
      [tx.id, tx.user_id, tx.type, tx.method, tx.status, tx.approval_status]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(q)),
    );
  }, [txs, query]);

  const filteredUsers = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return users;
    return users.filter((user) =>
      [user.username, user.fullname, user.country, user.user_id, user.kyc_status]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(q)),
    );
  }, [users, query]);

  if (allowed === false) {
    return <Navigate to="/admin/login" replace />;
  }

  return (
    <div className="mx-auto max-w-[1440px] px-4 py-5 pb-28 sm:px-6 sm:py-8">
      <header className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div className="mb-2 inline-flex items-center gap-2 rounded-full border border-accent/30 bg-accent/10 px-3 py-1 text-[11px] font-semibold uppercase tracking-wider text-accent">
            <ShieldCheck size={14} /> {adminRole}
          </div>
          <h1 className="text-2xl font-bold text-fg sm:text-3xl">Admin Control Center</h1>
          <p className="mt-1 text-sm text-muted">
            Secure oversight for users, balances and transaction approvals.
          </p>
        </div>
        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="inline-flex items-center justify-center gap-2 rounded-xl border border-line bg-panel px-4 py-2.5 text-sm font-medium text-fg hover:bg-elevated disabled:opacity-60"
        >
          <RefreshCw size={16} className={loading ? "animate-spin" : ""} />
          Refresh
        </button>
      </header>

      {error && (
        <div className="mb-5 flex gap-3 rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-300">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {loading ? (
        <div className="rounded-2xl border border-line bg-panel py-20 text-center text-muted">
          Loading secure admin data…
        </div>
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Stat icon={Clock} label="Awaiting approval" value={pending.length} />
            <Stat icon={CheckCircle} label="Approved / ready" value={approved.length} />
            <Stat icon={Users} label="Registered users" value={users.length} />
            <Stat icon={Wallet} label="User balances" value={money(totalBalance)} />
          </div>

          <div className="mt-3 rounded-xl border border-line bg-panel px-4 py-3 text-sm text-muted">
            <span className="font-medium text-fg">{pendingKyc}</span> user
            {pendingKyc === 1 ? "" : "s"} currently awaiting KYC review.
          </div>

          <section className="mt-6 overflow-hidden rounded-2xl border border-line bg-panel">
            <div className="flex flex-col gap-3 border-b border-line p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
              <div className="flex rounded-xl bg-elevated p-1">
                <TabButton active={tab === "transactions"} onClick={() => setTab("transactions")}>
                  Transactions
                </TabButton>
                <TabButton active={tab === "users"} onClick={() => setTab("users")}>
                  Users
                </TabButton>
              </div>
              <label className="flex items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 sm:min-w-[280px]">
                <Search size={16} className="text-muted" />
                <input
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                  placeholder={tab === "users" ? "Search users…" : "Search transactions…"}
                  className="min-w-0 flex-1 bg-transparent text-sm text-fg outline-none placeholder:text-muted"
                />
              </label>
            </div>

            {tab === "transactions" ? (
              <div className="divide-y divide-line">
                {filteredTransactions.length === 0 ? (
                  <EmptyState text="No transactions found." />
                ) : (
                  filteredTransactions.map((tx) => (
                    <div key={tx.id} className="p-4 sm:p-5">
                      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="font-semibold capitalize text-fg">
                              {tx.type}
                            </span>
                            <Status value={tx.approval_status} />
                            <span className="text-lg font-semibold text-fg">
                              {money(tx.amount)}
                            </span>
                          </div>
                          <p className="mt-1 text-sm text-muted">
                            {tx.method || "No method"} · {new Date(tx.created_at).toLocaleString()}
                          </p>
                          <p className="mt-1 break-all text-xs text-subtle">
                            User: {tx.user_id}
                          </p>
                          {tx.note && (
                            <p className="mt-2 text-xs text-muted">{tx.note}</p>
                          )}
                        </div>

                        <div className="flex shrink-0 flex-wrap gap-2">
                          {tx.approval_status === "awaiting" && (
                            <>
                              <button
                                type="button"
                                disabled={busy === tx.id}
                                onClick={() => void act("approve", tx.id)}
                                className="inline-flex items-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60"
                              >
                                <CheckCircle size={16} /> Approve
                              </button>
                              <button
                                type="button"
                                disabled={busy === tx.id}
                                onClick={() => {
                                  setRejectId(tx.id);
                                  setRejectReason("");
                                }}
                                className="inline-flex items-center gap-2 rounded-xl border border-red-500/40 px-4 py-2.5 text-sm font-medium text-red-300 disabled:opacity-60"
                              >
                                <XCircle size={16} /> Reject
                              </button>
                            </>
                          )}
                          {tx.approval_status === "approved" && tx.status !== "completed" && (
                            <button
                              type="button"
                              disabled={busy === tx.id}
                              onClick={() => void act("settle", tx.id)}
                              className="inline-flex items-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60"
                            >
                              <CheckCircle size={16} /> Settle
                            </button>
                          )}
                        </div>
                      </div>

                      {rejectId === tx.id && (
                        <div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/5 p-4">
                          <label className="block text-xs font-semibold uppercase tracking-wide text-muted">
                            Rejection reason
                          </label>
                          <textarea
                            value={rejectReason}
                            onChange={(event) => setRejectReason(event.target.value)}
                            rows={3}
                            maxLength={500}
                            placeholder="Explain why this transaction is being rejected…"
                            className="mt-2 w-full rounded-xl border border-line bg-surface p-3 text-sm text-fg outline-none focus:border-accent"
                          />
                          <div className="mt-3 flex gap-2">
                            <button
                              type="button"
                              disabled={busy === tx.id || !rejectReason.trim()}
                              onClick={() => void act("reject", tx.id, rejectReason.trim())}
                              className="rounded-xl bg-red-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
                            >
                              Confirm rejection
                            </button>
                            <button
                              type="button"
                              onClick={() => setRejectId(null)}
                              className="rounded-xl border border-line px-4 py-2 text-sm"
                            >
                              Cancel
                            </button>
                          </div>
                        </div>
                      )}
                    </div>
                  ))
                )}
              </div>
            ) : (
              <div className="divide-y divide-line">
                {filteredUsers.length === 0 ? (
                  <EmptyState text="No users found." />
                ) : (
                  filteredUsers.map((user) => (
                    <div key={user.id} className="p-4 sm:p-5">
                      <div className="grid gap-4 sm:grid-cols-[1.5fr_1fr_1fr_auto] sm:items-center">
                        <div className="min-w-0">
                          <div className="font-semibold text-fg">
                            {user.fullname || user.username || "Unnamed user"}
                          </div>
                          <div className="text-xs text-muted">
                            @{user.username || "—"} · {user.country || "Country not set"}
                          </div>
                          <div className="mt-1 break-all text-[11px] text-subtle">
                            {user.user_id}
                          </div>
                        </div>
                        <div>
                          <div className="text-[11px] uppercase tracking-wide text-muted">
                            Balance
                          </div>
                          <div className="font-semibold text-fg">{money(user.available_balance)}</div>
                        </div>
                        <div>
                          <div className="text-[11px] uppercase tracking-wide text-muted">
                            Deposits / Withdrawals
                          </div>
                          <div className="text-sm text-fg">
                            {money(user.total_deposits)} / {money(user.total_withdrawals)}
                          </div>
                        </div>
                        <Status value={user.kyc_status || "pending"} />
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}

function Stat({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof Clock;
  label: string;
  value: string | number;
}) {
  return (
    <div className="rounded-2xl border border-line bg-panel p-4 sm:p-5">
      <div className="flex items-center gap-2 text-xs font-medium text-muted">
        <Icon size={16} /> {label}
      </div>
      <div className="mt-2 text-2xl font-bold text-fg">{value}</div>
    </div>
  );
}

function TabButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        active
          ? "rounded-lg bg-panel px-4 py-2 text-sm font-semibold text-fg shadow-sm"
          : "rounded-lg px-4 py-2 text-sm text-muted"
      }
    >
      {children}
    </button>
  );
}

function Status({ value }: { value: string }) {
  const normalized = value.toLowerCase();
  const positive = ["approved", "completed", "verified"].includes(normalized);
  const negative = ["rejected", "failed"].includes(normalized);
  return (
    <span
      className={
        "inline-flex rounded-full border px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide " +
        (positive
          ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-300"
          : negative
            ? "border-red-500/30 bg-red-500/10 text-red-300"
            : "border-amber-500/30 bg-amber-500/10 text-amber-300")
      }
    >
      {value}
    </span>
  );
}

function EmptyState({ text }: { text: string }) {
  return <div className="p-10 text-center text-sm text-muted">{text}</div>;
}
