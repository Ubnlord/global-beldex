import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import { copy, fill, type Lang } from "./i18n";
import { planCeiling, type Plan } from "./catalog";
import { bdxToUsd, uid } from "@/lib/utils";
import { fetchQuotes } from "@/lib/market/live-quotes";
import { pullCloudBook } from "@/lib/supabase/books";
import { supabase } from "@/lib/supabase/client";
import type { CloudProfile } from "@/lib/supabase/auth";
import { validateWithdrawalDestination } from "@/lib/financial/withdrawal-address";
import { runWithFailureFallback } from "@/lib/supabase/refresh-safety";

export type { Lang };

export type TxType =
  | "deposit"
  | "withdraw"
  | "bonus"
  | "plan"
  | "swap"
  | "referral";
export type TxStatus = "pending" | "completed" | "failed";

export type Transaction = {
  id: string;
  type: TxType;
  amount: number;
  status: TxStatus;
  date: string;
  method: string;
  note?: string;
  /** Epoch ms when a pending deposit or withdrawal should finish. */
  settleAt?: number;
};

export type User = {
  name: string;
  username: string;
  email: string;
  phone: string;
  country: string;
  ref?: string;
  avatar?: string;
};

export type ActivePlan = {
  id: string;
  planId: string;
  name: string;
  amount: number;
  dailyPct: number;
  startedAt: number;
  durationDays: number;
  status: "active" | "completed";
  color: string;
  /** Full days of interest already added to the simulated balance. */
  creditedDays?: number;
  creditedProfit?: number;
  lastAccrualAt?: number;
};

export type Notice = {
  id: string;
  title: string;
  body: string;
  time: number;
  read: boolean;
};

export type Ticket = {
  id: string;
  subject: string;
  body: string;
  time: number;
  status: "open" | "answered";
};

export type Book = {
  available: number;
  bdx: number;
  locked: number;
  profit: number;
  bonus: number;
  referralBonus: number;
  withdrawn: number;
  txs: Transaction[];
  plans: ActivePlan[];
  notices: Notice[];
  tickets: Ticket[];
  /** True when the latest cloud hydration could not run server-side accrual. */
  accrualFailed: boolean;
};

type PlatformState = {
  hydrated: boolean;
  setHydrated: (v: boolean) => void;
  user: User | null;
  available: number;
  bdx: number;
  locked: number;
  profit: number;
  bonus: number;
  referralBonus: number;
  withdrawn: number;
  txs: Transaction[];
  plans: ActivePlan[];
  notices: Notice[];
  tickets: Ticket[];
  accrualFailed: boolean;
  lang: Lang;
  setLang: (lang: Lang) => void;
  notificationSound: boolean;
  setNotificationSound: (enabled: boolean) => void;
  welcomeOpen: boolean;
  dismissWelcome: () => void;
  sessionOnly: boolean;
  setSessionOnly: (v: boolean) => void;
  setUserProfile: (user: User | CloudProfile) => void;
  logout: () => void;
  updateProfile: (patch: Partial<User>) => void;
  deposit: (amount: number, method: string, requestId?: string, currency?: "BDX" | "USD") => Promise<string | null>;
  withdraw: (amount: number, method: string, address: string, requestId?: string, currency?: "BDX" | "USD") => Promise<string | null>;
  buyPlan: (plan: Plan, amount: number) => Promise<string | null>;
  settlePlans: () => Promise<void>;
  swap: (from: "USD" | "BDX", to: "USD" | "BDX", amount: number, rate?: number) => Promise<string | null>;
  copyReferral: () => string;
  addNotice: (title: string, body: string) => void;
  markNoticesRead: () => void;
  submitTicket: (subject: string, body: string) => string | null;
  refreshTransactions: () => Promise<void>;
};

function notice(title: string, body: string): Notice {
  return { id: uid(), title, body, time: Date.now(), read: false };
}

function emptyBook(): Book {
  return {
    available: 0,
    bdx: 0,
    locked: 0,
    profit: 0,
    bonus: 0,
    referralBonus: 0,
    withdrawn: 0,
    txs: [],
    plans: [],
    notices: [],
    tickets: [],
    accrualFailed: false,
  };
}

function snapshot(s: Book): Book {
  return {
    available: s.available,
    bdx: s.bdx,
    locked: s.locked,
    profit: s.profit,
    bonus: s.bonus,
    referralBonus: s.referralBonus,
    withdrawn: s.withdrawn,
    txs: s.txs,
    plans: s.plans,
    notices: s.notices,
    tickets: s.tickets ?? [],
    accrualFailed: s.accrualFailed ?? false,
  };
}

export const usePlatform = create<PlatformState>()(
  persist(
    (set, get) => {
      return {
        hydrated: false,
        setHydrated: (v) => set({ hydrated: v }),
        user: null,
        ...emptyBook(),
        lang: "en",
        setLang: (lang) => set({ lang }),
        notificationSound: true,
        setNotificationSound: (enabled) => set({ notificationSound: enabled }),
        welcomeOpen: true,
        dismissWelcome: () => set({ welcomeOpen: false }),
        sessionOnly: false,
        setSessionOnly: (v) => set({ sessionOnly: v }),

        setUserProfile: (profile) =>
          set({
            user:
              "name" in profile
                ? profile
                : {
                    name: profile.fullname,
                    username: profile.username,
                    email: profile.email,
                    phone: profile.phone,
                    country: profile.country,
                    ref: profile.ref,
                    avatar: profile.avatar,
                  },
            welcomeOpen: true,
          }),

        logout: () => {
          set({ user: null, welcomeOpen: true, ...emptyBook() });
        },

        updateProfile: (patch) => {
          const user = get().user;
          if (!user) return;
          set({ user: { ...user, ...patch } });
        },

        refreshTransactions: async () => {
          const { data: { user } } = await supabase.auth.getUser();
          if (!user) return;

          const { data, error } = await supabase
            .from("transaction")
            .select("id,type,amount,status,method,note,created_at")
            .eq("user_id", user.id)
            .order("created_at", { ascending: false });

          if (error) return;

          const txs: Transaction[] = (data ?? []).map((t: any) => ({
            id: t.id,
            type: t.type as TxType,
            amount: Number.isFinite(Number(t.amount)) ? Number(t.amount) : 0,
            status: (t.status === "completed"
              ? "completed"
              : t.status === "failed"
                ? "failed"
                : "pending") as TxStatus,
            date: new Date(t.created_at).toISOString(),
            method: t.method ?? undefined,
            note: t.note ?? undefined,
          }));

          set({ txs });
        },

        deposit: async (amount, method, requestId, currency = "BDX") => {
          const isBeldex = method === "BELDEX";
          const usdAmount = isBeldex && currency === "BDX" ? bdxToUsd(amount) : amount;
          if (!amount || (isBeldex ? usdAmount < bdxToUsd(4000) : usdAmount < 300)) return "MIN_DEPOSIT";
          const { error } = await supabase.rpc("create_financial_transaction", {
            p_type: "deposit",
            p_amount: usdAmount,
            p_method: method,
            p_note: null,
            p_request_id: requestId ? requestId : null,
          });
          if (error) return error.message;
          await get().refreshTransactions();
          return null;
        },

        withdraw: async (amount, method, address, requestId, currency = "BDX") => {
          if (!method) return "NEED_METHOD";
          const addressError = validateWithdrawalDestination(method, address);
          if (addressError) return addressError;
          if (!amount || amount <= 0) return "NEED_AMOUNT";
          const usdAmount = method === "Beldex" && currency === "BDX" ? bdxToUsd(amount) : amount;
          if (usdAmount < (method === "Beldex" ? bdxToUsd(4000) : 300)) return "MIN_WITHDRAWAL";
          if (usdAmount > get().available) return "INSUFFICIENT";
          const { error } = await supabase.rpc("create_financial_transaction", {
            p_type: "withdraw",
            p_amount: usdAmount,
            p_method: method,
            p_note: address.trim(),
            p_request_id: requestId ? requestId : null,
          });
          if (error) return error.message;
          await get().refreshTransactions();
          return null;
        },

        buyPlan: async (plan, amount) => {
          if (amount < plan.min) return "MIN_PLAN|" + plan.name + "|" + plan.min.toLocaleString();
          const cap = planCeiling(plan);
          if (cap != null && amount > cap) return "MAX_PLAN|" + plan.name + "|" + cap.toLocaleString();
          // Plan amounts are entered/displayed in BDX, but the server ledger is USD-denominated.
          // Convert exactly once at the RPC boundary: 4,000 BDX => $293.984 USD.
          // Use the protected live BDX/USD market quote at purchase time.
          // The fixed conversion is only the emergency fallback if all feeds are unavailable.
          const liveQuote = await fetchQuotes();
          const usdAmount = amount * liveQuote.beldex.usd;
          const { error } = await supabase.rpc("buy_investment_plan", {
            p_plan_id: plan.id,
            p_amount: usdAmount,
          });
          if (error) return error.message;
          const remote = await pullCloudBook();
          if (remote) set({ ...remote, tickets: remote.tickets ?? [] });
          return null;
        },

        settlePlans: async () => {
          const remote = await runWithFailureFallback(async () => {
            const { error } = await supabase.rpc("accrue_user_investments", { p_user_id: null });
            if (error) throw error;
            return await pullCloudBook({ skipAccrual: true });
          }, () => {
            // Rejected network/RPC promises must never clear saved financial values.
            set({ accrualFailed: true });
          });
          if (remote) {
            set({ ...remote, tickets: remote.tickets ?? [] });
          } else {
            // Never clear or zero financial values after an incomplete cloud refresh.
            set({ accrualFailed: true });
          }
        },

        swap: async (from, to, amount) => {
          if (from === to) return "SWAP_SAME";
          if (!amount || amount <= 0) return "NEED_AMOUNT";

          const { error } = await supabase.functions.invoke("swap-assets", {
            body: { from, to, amount },
          });
          if (error) return error.message;

          const remote = await pullCloudBook();
          if (remote) set({ ...remote, tickets: remote.tickets ?? [] });
          return null;
        },
        copyReferral: () => referralLink(get().user),

        addNotice: (title, body) => {
          set({ notices: [notice(title, body), ...get().notices] });
        },
        markNoticesRead: () => {
          set({ notices: get().notices.map((n) => ({ ...n, read: true })) });
        },

        submitTicket: (subject, body) => {
          if (!subject.trim() || !body.trim()) return "NEED_TICKET";
          const ticket: Ticket = {
            id: uid(),
            subject: subject.trim(),
            body: body.trim(),
            time: Date.now(),
            status: "answered",
          };
          const m = copy[get().lang].note;
          set({
            tickets: [ticket, ...(get().tickets ?? [])],
            notices: [
              notice(m.supportTitle, fill(m.supportBody, { subject: ticket.subject })),
              ...get().notices,
            ],
          });
          return null;
        },

      };
    },
    {
      name: "logan-beldex-v1",
      version: 2,
      storage: createJSONStorage(() => localStorage),
      skipHydration: true,
      migrate: (persisted) => {
        const p = (persisted ?? {}) as Partial<PlatformState>;
        const tickets = p.tickets ?? [];
        const book = snapshot({
          available: p.available ?? 0,
          bdx: p.bdx ?? 0,
          locked: p.locked ?? 0,
          profit: p.profit ?? 0,
          bonus: p.bonus ?? 0,
          referralBonus: p.referralBonus ?? 0,
          withdrawn: p.withdrawn ?? 0,
          txs: p.txs ?? [],
          plans: p.plans ?? [],
          notices: p.notices ?? [],
          tickets,
          accrualFailed: p.accrualFailed ?? false,
        });
        return { ...p, tickets, user: null };
      },
      partialize: (s) => ({
        lang: s.lang,
        notificationSound: s.notificationSound,
        welcomeOpen: s.welcomeOpen,
        sessionOnly: s.sessionOnly,
      }),
    },
  ),
);

export function referralLink(user: User | null) {
  // Username is accepted by ensure_user_profile as a referral lookup key.
  // Do not use user.ref here: before profile hydration it can still contain
  // the sponsor's code from signup metadata rather than this user's own code.
  const code = user?.username?.trim();
  const base = "https://global-beldex.com/register";
  return code ? `${base}?ref=${encodeURIComponent(code)}` : base;
}

export function accruedProfit(p: ActivePlan, now = Date.now()) {
  const elapsed = Math.min(
    p.durationDays,
    Math.max(0, (now - p.startedAt) / 86_400_000),
  );
  return p.amount * (p.dailyPct / 100) * elapsed;
}

