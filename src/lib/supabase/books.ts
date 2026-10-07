import type { Book, ActivePlan, Transaction, TxStatus, TxType } from "@/lib/platform/store";
import { supabase } from "./client";

function num(v: unknown) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

export async function pullCloudBook(): Promise<Book | null> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  // Accrual is idempotent: PostgreSQL only credits elapsed days not already processed.
  await supabase.rpc("accrue_user_investments", { p_user_id: null });

  const [profileResult, txResult, investmentsResult] = await Promise.all([
    supabase
      .from("user_profile")
      .select("available_balance,locked_balance,total_withdrawals,bdx_balance,referral_earnings")
      .eq("user_id", user.id)
      .maybeSingle(),
    supabase
      .from("transaction")
      .select("id,type,amount,status,method,note,created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false }),
    supabase
      .from("user_investment")
      .select("id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,credited_profit,status,investment_plan_catalog(name)")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false }),
  ]);

  if (profileResult.error) return null;
  const p = profileResult.data;
  const rawTxs = txResult.data ?? [];
  const txs: Transaction[] = rawTxs.map((t: any) => ({
    id: t.id,
    type: t.type as TxType,
    amount: num(t.amount),
    status: (t.status === "completed" ? "completed" : t.status === "failed" ? "failed" : "pending") as TxStatus,
    date: new Date(t.created_at).toISOString(),
    method: t.method ?? undefined,
    note: t.note ?? undefined,
  }));

  const plans: ActivePlan[] = (investmentsResult.data ?? []).map((p: any) => {
    const catalog = Array.isArray(p.investment_plan_catalog)
      ? p.investment_plan_catalog[0]
      : p.investment_plan_catalog;
    return {
      id: p.id,
      planId: p.plan_id,
      name: catalog?.name ?? p.plan_id,
      amount: num(p.principal),
      dailyPct: num(p.daily_rate) * 100,
      startedAt: new Date(p.started_at).getTime(),
      durationDays: Number(p.duration_days) || 0,
      status: p.status === "completed" ? "completed" : "active",
      color: "#2AF5D4",
      creditedDays: undefined,
      creditedProfit: num(p.credited_profit),
      lastAccrualAt: p.last_accrual_at ? new Date(p.last_accrual_at).getTime() : undefined,
    };
  });

  const profit = (investmentsResult.data ?? []).reduce(
    (sum: number, p: any) => sum + num(p.credited_profit),
    0,
  );
  const bonus = rawTxs
    .filter((t: any) => t.type === "bonus" && t.method === "Welcome Bonus")
    .reduce((sum: number, t: any) => sum + num(t.amount), 0);

  return {
    available: num(p?.available_balance),
    bdx: num(p?.bdx_balance),
    locked: num(p?.locked_balance),
    profit,
    bonus,
    referralBonus: num(p?.referral_earnings),
    withdrawn: num(p?.total_withdrawals),
    txs,
    plans,
    notices: [],
    tickets: [],
  };
}

// Legacy client-ledger writes are intentionally disabled.
export async function pushCloudBook(_book: Book) { return; }
export function scheduleCloudSave(_book: Book) { return; }
