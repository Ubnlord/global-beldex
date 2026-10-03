import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import { copy, fill, type Lang } from "./i18n";
import { planCeiling, type Plan } from "./catalog";
import { formatDate, uid } from "@/lib/utils";

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
};

type AccountRecord = {
  password: string;
  user: User;
  twoFactor?: string | null;
  book?: Book;
};

type PlatformState = {
  hydrated: boolean;
  setHydrated: (v: boolean) => void;
  user: User | null;
  accounts: Record<string, AccountRecord>;
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
  lang: Lang;
  setLang: (lang: Lang) => void;
  welcomeOpen: boolean;
  dismissWelcome: () => void;
  sessionOnly: boolean;
  setSessionOnly: (v: boolean) => void;
  login: (email: string, password: string, code?: string) => string | null;
  register: (input: {
    username: string;
    fullname: string;
    email: string;
    phone: string;
    country: string;
    pass: string;
    ref?: string;
  }) => string | null;
  enterAccount: (input: {
    email: string;
    username?: string;
    fullname?: string;
    phone?: string;
    country?: string;
    ref?: string;
  }) => string | null;
  logout: () => void;
  updateProfile: (patch: Partial<User>) => void;
  changePassword: (current: string, next: string) => string | null;
  resetPassword: (email: string, next: string) => string | null;
  setTwoFactor: (on: boolean) => string | null;
  deposit: (amount: number, method: string) => string | null;
  settlePending: () => void;
  withdraw: (amount: number, method: string, address: string) => string | null;
  buyPlan: (plan: Plan, amount: number) => string | null;
  settlePlans: () => void;
  swap: (from: "USD" | "BDX", to: "USD" | "BDX", amount: number, rate: number) => string | null;
  copyReferral: () => string;
  addNotice: (title: string, body: string) => void;
  markNoticesRead: () => void;
  submitTicket: (subject: string, body: string) => string | null;
  requestReset: (email: string) => string | null;
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
  };
}

function lookupAccount(accounts: Record<string, AccountRecord>, token: string) {
  const raw = token.trim();
  if (!raw) return null;
  const matched = raw.match(/\/ref\/([^/?#]+)/i);
  const slug = decodeURIComponent(matched?.[1] ?? raw).trim().toLowerCase();
  if (!slug) return null;
  if (accounts[slug]) return { key: slug, rec: accounts[slug] };
  for (const [key, rec] of Object.entries(accounts)) {
    if (
      rec.user.username.toLowerCase() === slug ||
      rec.user.email.toLowerCase() === slug
    ) {
      return { key, rec };
    }
  }
  return null;
}

function creditReferrer(
  get: () => PlatformState,
  set: (partial: Partial<PlatformState>) => void,
  depositAmount: number,
) {
  const s = get();
  const user = s.user;
  if (!user?.ref) return;
  const found = lookupAccount(s.accounts, user.ref);
  if (!found || found.key === user.email.toLowerCase()) return;
  const cut = Math.round(depositAmount * 10) / 100;
  if (cut <= 0) return;
  const book = found.rec.book ?? emptyBook();
  const m = copy[s.lang].note;
  const tx: Transaction = {
    id: uid(),
    type: "referral",
    amount: cut,
    status: "completed",
    date: formatDate(),
    method: user.username,
  };
  const nextBook: Book = {
    ...book,
    available: book.available + cut,
    referralBonus: book.referralBonus + cut,
    txs: [tx, ...book.txs],
    notices: [
      notice(
        m.referralTitle,
        fill(m.referralBody, { user: user.username, amount: cut.toFixed(2) }),
      ),
      ...book.notices,
    ],
  };
  set({
    accounts: {
      ...get().accounts,
      [found.key]: { ...found.rec, book: nextBook },
    },
  });
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
  };
}

function settle(plans: ActivePlan[], now: number) {
  let extraBalance = 0;
  let extraProfit = 0;
  const next = plans.map((p) => {
    if (p.status !== "active") return p;
    const credited = p.creditedDays ?? 0;
    const elapsedDays = Math.min(
      p.durationDays,
      Math.max(0, Math.floor((now - p.startedAt) / 86_400_000)),
    );
    const newly = Math.max(0, elapsedDays - credited);
    const dayEarn = p.amount * (p.dailyPct / 100);
    const earned = dayEarn * newly;
    extraBalance += earned;
    extraProfit += earned;
    const done = now >= p.startedAt + p.durationDays * 86_400_000;
    if (done) {
      extraBalance += p.amount;
      return { ...p, status: "completed" as const, creditedDays: p.durationDays };
    }
    if (newly === 0) return p;
    return { ...p, creditedDays: credited + newly };
  });
  return { plans: next, extraBalance, extraProfit };
}

export const usePlatform = create<PlatformState>()(
  persist(
    (set, get) => {
      const save = () => {
        const s = get();
        if (!s.user) return;
        const key = s.user.email.toLowerCase();
        const rec = s.accounts[key];
        if (!rec) return;
        set({
          accounts: {
            ...s.accounts,
            [key]: { ...rec, user: s.user, book: snapshot(s) },
          },
        });
      };

      return {
        hydrated: false,
        setHydrated: (v) => set({ hydrated: v }),
        user: null,
        accounts: {},
        ...emptyBook(),
        lang: "en",
        setLang: (lang) => set({ lang }),
        welcomeOpen: true,
        dismissWelcome: () => set({ welcomeOpen: false }),
        sessionOnly: false,
        setSessionOnly: (v) => set({ sessionOnly: v }),

        login: (email, password, code) => {
          const key = email.trim().toLowerCase();
          if (!key || !password) return "FILL";
          const found = lookupAccount(get().accounts, key);
          if (!found) return "NO_ACCOUNT";
          if (found.rec.password !== password) return "BAD_PASSWORD";
          if (found.rec.twoFactor) {
            if (!code) return "2FA";
            if (code.trim() !== found.rec.twoFactor) return "BAD_CODE";
          }
          const book = found.rec.book ?? emptyBook();
          set({
            user: found.rec.user,
            welcomeOpen: true,
            ...book,
            tickets: book.tickets ?? [],
          });
          get().settlePlans();
          get().settlePending();
          return null;
        },

        register: (input) => {
          const email = input.email.trim().toLowerCase();
          const username = input.username.trim();
          if (!username || !email || !input.pass) return "FILL";
          if (get().accounts[email]) return "EMAIL_TAKEN";
          let refUser: string | undefined;
          const refRaw = input.ref?.trim();
          if (refRaw) {
            const found = lookupAccount(get().accounts, refRaw);
            if (!found) return "BAD_REF";
            if (
              found.key === email ||
              found.rec.user.username.toLowerCase() === username.toLowerCase()
            ) {
              return "REF_SELF";
            }
            refUser = found.rec.user.username;
          }
          const m = copy[get().lang].note;
          const user: User = {
            name: input.fullname || username,
            username,
            email,
            phone: input.phone,
            country: input.country,
            ref: refUser,
          };
          const bonusTx: Transaction = {
            id: uid(),
            type: "bonus",
            amount: 3,
            status: "completed",
            date: formatDate(),
            method: "Welcome Bonus",
          };
          const book: Book = {
            ...emptyBook(),
            available: 3,
            bonus: 3,
            txs: [bonusTx],
            notices: [notice(m.welcomeTitle, m.welcomeBody)],
          };
          set({
            user,
            accounts: { ...get().accounts, [email]: { password: input.pass, user, book } },
            ...book,
            welcomeOpen: true,
          });
          return null;
        },

        enterAccount: (input) => {
          const email = input.email.trim().toLowerCase();
          const username = (input.username || email.split("@")[0] || "member").trim();
          if (!email) return "FILL";
          const found = lookupAccount(get().accounts, email);
          if (found) {
            if (get().user?.email.toLowerCase() === found.key) return null;
            const book = found.rec.book ?? emptyBook();
            set({
              user: found.rec.user,
              welcomeOpen: true,
              ...book,
              tickets: book.tickets ?? [],
            });
            get().settlePlans();
            get().settlePending();
            return null;
          }
          let refUser: string | undefined;
          const refRaw = input.ref?.trim();
          if (refRaw) {
            const refFound = lookupAccount(get().accounts, refRaw);
            if (
              refFound &&
              refFound.key !== email &&
              refFound.rec.user.username.toLowerCase() !== username.toLowerCase()
            ) {
              refUser = refFound.rec.user.username;
            }
          }
          const m = copy[get().lang].note;
          const user: User = {
            name: input.fullname || username,
            username,
            email,
            phone: input.phone || "",
            country: input.country || "",
            ref: refUser,
          };
          const bonusTx: Transaction = {
            id: uid(),
            type: "bonus",
            amount: 3,
            status: "completed",
            date: formatDate(),
            method: "Welcome Bonus",
          };
          const book: Book = {
            ...emptyBook(),
            available: 3,
            bonus: 3,
            txs: [bonusTx],
            notices: [notice(m.welcomeTitle, m.welcomeBody)],
          };
          set({
            user,
            accounts: { ...get().accounts, [email]: { password: "", user, book } },
            ...book,
            welcomeOpen: true,
          });
          return null;
        },

        logout: () => {
          save();
          set({ user: null, welcomeOpen: true, ...emptyBook() });
        },

        updateProfile: (patch) => {
          const user = get().user;
          if (!user) return;
          const next = { ...user, ...patch };
          const accounts = { ...get().accounts };
          const rec = accounts[user.email.toLowerCase()];
          if (rec) accounts[user.email.toLowerCase()] = { ...rec, user: next };
          set({ user: next, accounts });
          save();
        },

        changePassword: (current, next) => {
          const user = get().user;
          if (!user) return "SIGN_IN";
          if (!next || next.length < 4) return "SHORT_PASSWORD";
          const key = user.email.toLowerCase();
          const rec = get().accounts[key];
          if (!rec || rec.password !== current) return "BAD_CURRENT";
          set({
            accounts: { ...get().accounts, [key]: { ...rec, password: next } },
          });
          const m = copy[get().lang].note;
          get().addNotice(m.passwordTitle, m.passwordBody);
          return null;
        },

        resetPassword: (email, next) => {
          const keyIn = email.trim().toLowerCase();
          if (!keyIn) return "NEED_EMAIL";
          if (!next || next.length < 4) return "SHORT_PASSWORD";
          const found = lookupAccount(get().accounts, keyIn);
          if (!found) return null;
          const m = copy[get().lang].note;
          const book = found.rec.book ?? emptyBook();
          set({
            accounts: {
              ...get().accounts,
              [found.key]: {
                ...found.rec,
                password: next,
                book: {
                  ...book,
                  notices: [notice(m.passwordTitle, m.passwordBody), ...book.notices],
                },
              },
            },
          });
          return null;
        },

        setTwoFactor: (on) => {
          const user = get().user;
          if (!user) return null;
          const key = user.email.toLowerCase();
          const rec = get().accounts[key];
          if (!rec) return null;
          const code = on ? String(Math.floor(100000 + Math.random() * 900000)) : null;
          set({
            accounts: { ...get().accounts, [key]: { ...rec, twoFactor: code } },
          });
          const m = copy[get().lang].note;
          get().addNotice(
            on ? m.twoOnTitle : m.twoOffTitle,
            on ? fill(m.twoOnBody, { code: code ?? "" }) : m.twoOffBody,
          );
          return code;
        },

        deposit: (amount, method) => {
          if (!amount || amount < 300) return "MIN_DEPOSIT";
          const m = copy[get().lang].note;
          const tx: Transaction = {
            id: uid(),
            type: "deposit",
            amount,
            status: "pending",
            date: formatDate(),
            method,
            settleAt: Date.now() + 1800,
          };
          set({
            txs: [tx, ...get().txs],
            notices: [
              notice(
                m.depositInitTitle,
                fill(m.depositInitBody, { method, amount: amount.toFixed(2) }),
              ),
              ...get().notices,
            ],
          });
          save();
          return null;
        },

        settlePending: () => {
          const now = Date.now();
          const s0 = get();
          if (!s0.user) return;
          const due = s0.txs.filter(
            (t) =>
              t.status === "pending" &&
              (t.type === "deposit" || t.type === "withdraw") &&
              (t.settleAt ?? 0) <= now,
          );
          if (due.length === 0) return;
          const m = copy[s0.lang].note;
          let available = s0.available;
          const notices = [...s0.notices];
          const ids = new Set(due.map((t) => t.id));
          for (const tx of due) {
            if (tx.type === "deposit") {
              available += tx.amount;
              notices.unshift(
                notice(m.depositDoneTitle, fill(m.depositDoneBody, { amount: tx.amount.toFixed(2) })),
              );
            } else {
              notices.unshift(
                notice(
                  m.withdrawDoneTitle,
                  fill(m.withdrawDoneBody, { amount: tx.amount.toFixed(2), method: tx.method }),
                ),
              );
            }
          }
          set({
            available,
            notices,
            txs: s0.txs.map((t) => (ids.has(t.id) ? { ...t, status: "completed" as const } : t)),
          });
          for (const tx of due) {
            if (tx.type === "deposit") creditReferrer(get, set, tx.amount);
          }
          save();
        },

        withdraw: (amount, method, address) => {
          if (!method) return "NEED_METHOD";
          if (!address.trim()) return "NEED_ADDRESS";
          if (!amount || amount <= 0) return "NEED_AMOUNT";
          if (amount > get().available) return "INSUFFICIENT";
          const m = copy[get().lang].note;
          const tx: Transaction = {
            id: uid(),
            type: "withdraw",
            amount,
            status: "pending",
            date: formatDate(),
            method,
            note: address.trim(),
            settleAt: Date.now() + 1600,
          };
          set({
            available: get().available - amount,
            withdrawn: get().withdrawn + amount,
            txs: [tx, ...get().txs],
            notices: [
              notice(
                m.withdrawReqTitle,
                fill(m.withdrawReqBody, { amount: amount.toFixed(2), method }),
              ),
              ...get().notices,
            ],
          });
          save();
          return null;
        },

        buyPlan: (plan, amount) => {
          if (amount < plan.min) return `MIN_PLAN|${plan.name}|${plan.min.toLocaleString()}`;
          const cap = planCeiling(plan);
          if (cap != null && amount > cap) return `MAX_PLAN|${plan.name}|${cap.toLocaleString()}`;
          if (amount > get().available) return "NEED_DEPOSIT";
          const m = copy[get().lang];
          const active: ActivePlan = {
            id: uid(),
            planId: plan.id,
            name: plan.name,
            amount,
            dailyPct: plan.dailyPct,
            startedAt: Date.now(),
            durationDays: plan.durationDays,
            status: "active",
            color: plan.color,
          };
          const tx: Transaction = {
            id: uid(),
            type: "plan",
            amount,
            status: "completed",
            date: formatDate(),
            method: plan.name,
          };
          set({
            available: get().available - amount,
            locked: get().locked + amount,
            plans: [active, ...get().plans],
            txs: [tx, ...get().txs],
            notices: [
              notice(
                fill(m.note.planTitle, { name: plan.name }),
                fill(m.note.planBody, {
                  amount: amount.toLocaleString(),
                  duration: `${plan.durationDays} ${m.days}`,
                }),
              ),
              ...get().notices,
            ],
          });
          save();
          return null;
        },

        settlePlans: () => {
          const prev = get().plans;
          const { plans, extraBalance, extraProfit } = settle(prev, Date.now());
          const released = prev
            .filter((p) => p.status === "active")
            .filter((p) => plans.find((n) => n.id === p.id)?.status === "completed")
            .reduce((s, p) => s + p.amount, 0);
          if (released === 0 && extraProfit === 0) return;
          const m = copy[get().lang].note;
          const matured = released > 0;
          set({
            plans,
            available: get().available + extraBalance,
            locked: Math.max(0, get().locked - released),
            profit: get().profit + extraProfit,
            txs:
              extraProfit > 0
                ? [
                    {
                      id: uid(),
                      type: "bonus" as const,
                      amount: extraProfit,
                      status: "completed" as const,
                      date: formatDate(),
                      method: matured ? "Plan maturity" : "Daily interest",
                    },
                    ...get().txs,
                  ]
                : get().txs,
            notices:
              extraProfit > 0 || matured
                ? [
                    matured
                      ? notice(
                          m.matureTitle,
                          fill(m.matureBody, {
                            amount: extraProfit.toFixed(2),
                          }),
                        )
                      : notice(
                          m.dailyTitle,
                          fill(m.dailyBody, { amount: extraProfit.toFixed(2) }),
                        ),
                    ...get().notices,
                  ]
                : get().notices,
          });
          save();
        },

        swap: (from, to, amount, rate) => {
          if (from === to) return "SWAP_SAME";
          if (!amount || amount <= 0) return "NEED_AMOUNT";
          if (!rate || rate <= 0) return "BAD_RATE";
          const m = copy[get().lang].note;
          if (from === "USD") {
            if (amount > get().available) return "INSUFFICIENT_USD";
            const out = amount / rate;
            const tx: Transaction = {
              id: uid(),
              type: "swap",
              amount,
              status: "completed",
              date: formatDate(),
              method: "USD → BDX",
              note: `${amount} USD → ${out.toFixed(4)} BDX`,
            };
            set({
              available: get().available - amount,
              bdx: get().bdx + out,
              txs: [tx, ...get().txs],
              notices: [notice(m.swapTitle, tx.note || ""), ...get().notices],
            });
            save();
            return null;
          }
          if (amount > get().bdx) return "INSUFFICIENT_BDX";
          const out = amount * rate;
          const tx: Transaction = {
            id: uid(),
            type: "swap",
            amount: out,
            status: "completed",
            date: formatDate(),
            method: "BDX → USD",
            note: `${amount} BDX → ${out.toFixed(2)} USD`,
          };
          set({
            bdx: get().bdx - amount,
            available: get().available + out,
            txs: [tx, ...get().txs],
            notices: [notice(m.swapTitle, tx.note || ""), ...get().notices],
          });
          save();
          return null;
        },

        copyReferral: () => {
          const u = get().user;
          const slug = u?.username || "guest";
          return `https://global-beldex.com/ref/${slug}`;
        },

        addNotice: (title, body) => {
          set({ notices: [notice(title, body), ...get().notices] });
          save();
        },
        markNoticesRead: () => {
          set({ notices: get().notices.map((n) => ({ ...n, read: true })) });
          save();
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
          save();
          return null;
        },

        requestReset: (email) => {
          if (!email.trim()) return "NEED_EMAIL";
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
        const p = (persisted ?? {}) as Partial<PlatformState> & {
          accounts?: Record<string, AccountRecord>;
        };
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
        });
        const accounts = { ...(p.accounts ?? {}) };
        const email = p.user?.email?.toLowerCase();
        if (email && accounts[email] && !accounts[email].book) {
          accounts[email] = { ...accounts[email], book };
        }
        return { ...p, accounts, tickets };
      },
      partialize: (s) => ({
        user: s.user,
        accounts: s.accounts,
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
        tickets: s.tickets,
        lang: s.lang,
        welcomeOpen: s.welcomeOpen,
        sessionOnly: s.sessionOnly,
      }),
    },
  ),
);

export function referralLink(user: User | null) {
  return `https://global-beldex.com/ref/${user?.username || "mrkenmk"}`;
}

export function accruedProfit(p: ActivePlan, now = Date.now()) {
  const elapsed = Math.min(
    p.durationDays,
    Math.max(0, (now - p.startedAt) / 86_400_000),
  );
  return p.amount * (p.dailyPct / 100) * elapsed;
}

export function twoFactorCode(
  accounts: Record<string, { twoFactor?: string | null }>,
  user: User | null,
) {
  if (!user) return null;
  return accounts[user.email.toLowerCase()]?.twoFactor ?? null;
}
