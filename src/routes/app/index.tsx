import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import type { ComponentType } from "react";
import {
  ArrowDownToLine,
  ArrowUpFromLine,
  Copy,
  ExternalLink,
  Gift,
  History,
  LayoutGrid,
  TrendingUp,
  Users,
  Wallet,
  X,
} from "lucide-react";
import { AdvancedChart, SymbolOverview } from "@/components/market/tradingview";
import { Button } from "@/components/ui/button";
import { toast } from "@/components/layout/toast";
import { TvCredit } from "@/components/platform/plan-card";
import { TxRow } from "@/components/platform/tx-row";
import { copy, fill } from "@/lib/platform/i18n";
import {
  accruedProfit,
  referralLink,
  usePlatform,
} from "@/lib/platform/store";
import { formatBdx, formatUsd, copyText } from "@/lib/utils";
export const Route = createFileRoute("/app/")({ component: Dashboard });

function Dashboard() {
  const navigate = useNavigate();
  const user = usePlatform((s) => s.user);
  const available = usePlatform((s) => s.available);
  const bdx = usePlatform((s) => s.bdx);
  const locked = usePlatform((s) => s.locked);
  const txs = usePlatform((s) => s.txs);
  const plans = usePlatform((s) => s.plans);
  const accrualFailed = usePlatform((s) => s.accrualFailed);
  const welcomeOpen = usePlatform((s) => s.welcomeOpen);
  const dismissWelcome = usePlatform((s) => s.dismissWelcome);
  const copyReferral = usePlatform((s) => s.copyReferral);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const active = plans.filter((p) => p.status === "active");
  const bdxProfit = plans.reduce((sum, p) => sum + (p.currency === "BDX" ? (p.creditedProfit ?? 0) : 0), 0);
  const bdxBonus = txs.filter((tx) => tx.type === "bonus" && tx.currency === "BDX" && tx.status === "completed").reduce((sum, tx) => sum + tx.amount, 0);
  const bdxReferralBonus = txs.filter((tx) => tx.type === "referral" && tx.currency === "BDX" && tx.status === "completed").reduce((sum, tx) => sum + tx.amount, 0);
  const bdxWithdrawn = txs.filter((tx) => tx.type === "withdraw" && tx.currency === "BDX" && tx.status === "completed").reduce((sum, tx) => sum + tx.amount, 0);

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      {accrualFailed && (
        <div role="alert" className="mb-4 rounded-lg border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-amber-200">
          We couldn't refresh your account data from the server. Your last saved balances are still shown; they may be out of date. Please refresh later or contact support if this continues.
        </div>
      )}
      {welcomeOpen && (
        <div className="mb-4 flex items-start justify-between rounded-lg border border-line-strong bg-elevated p-4">
          <div>
            <div className="text-sm font-semibold text-fg">{t.welcome}</div>
            <div className="mt-1 text-xs text-subtle">{t.welcomeBody}</div>
          </div>
          <button
            type="button"
            onClick={dismissWelcome}
            className="flex size-7 items-center justify-center rounded-full bg-surface text-subtle"
            aria-label="Dismiss"
          >
            <X size={14} />
          </button>
        </div>
      )}

      <div className="rounded-lg border border-line bg-elevated p-5">
        <div className="text-xs text-muted">BDX account overview</div>
        <div className="mt-1 text-lg font-bold text-fg">
          {t.hello} {user?.name || "Kenneth Munachimso"}!
        </div>
        <div className="mt-4 rounded-lg border border-emerald-500/40 bg-emerald-500/10 p-4">
          <div className="flex items-center gap-2 text-[11px] font-semibold text-emerald-300">
            <Wallet size={15} /> AVAILABLE BDX WALLET
          </div>
          <div className="mt-1 text-2xl font-extrabold tabular text-emerald-200">{formatBdx(bdx)}</div>
          <div className="mt-1 text-[10px] text-subtle">Available BDX balance · BDX investment profits and referral rewards stay in BDX</div>
        </div>
        <div className="mt-5 grid grid-cols-2 gap-3">
          <Stat icon={TrendingUp} label="BDX interest credited" value={formatBdx(bdxProfit)} tone="text-accent" />
          <Stat icon={Gift} label="BDX bonuses credited" value={formatBdx(bdxBonus)} tone="text-warn" />
          <Stat icon={Users} label="BDX referral rewards" value={formatBdx(bdxReferralBonus)} tone="text-violet" />
          <Stat icon={Wallet} label="BDX withdrawals completed" value={formatBdx(bdxWithdrawn)} tone="text-rose" />
        </div>
        <Button className="mt-5 w-full" onClick={() => navigate({ to: "/app/deposit" })}>
          <ArrowDownToLine size={16} /> {t.investNow}
        </Button>
        <Button
          className="mt-3 w-full bg-green-500 text-white hover:bg-green-400"
          onClick={() => navigate({ to: "/app/plans" })}
        >
          <TrendingUp size={16} /> {t.buyPlan}
        </Button>
      </div>

      <div className="mt-4 rounded-lg border border-line bg-surface p-4">
        <div className="text-[11px] font-semibold tracking-wide text-subtle">Historical USD balances · read-only reporting</div>
        <div className="mt-3 grid grid-cols-2 gap-4">
          <div>
            <div className="text-[11px] text-subtle">Available USD</div>
            <div className="text-lg font-bold tabular text-fg">{formatUsd(available)}</div>
          </div>
          <div>
            <div className="text-[11px] text-subtle">Locked USD</div>
            <div className="text-lg font-bold tabular text-fg">{formatUsd(locked)}</div>
          </div>
        </div>
        <p className="mt-2 text-[10px] text-subtle">These legacy USD figures are separate from the BDX wallet and are not converted or included in BDX totals.</p>
      </div>

      <div className="mt-4">
        <div className="text-[13px] font-semibold text-fg">{t.quick}</div>
        <div className="mt-3 grid grid-cols-4 gap-3">
          {[
            { label: t.deposit, icon: ArrowDownToLine, to: "/app/deposit" as const },
            { label: t.withdraw, icon: ArrowUpFromLine, to: "/app/withdraw" as const },
            { label: t.buyPlan, icon: TrendingUp, to: "/app/plans" as const },
            { label: t.history, icon: History, to: "/app/history" as const },
          ].map((a) => (
            <Link
              key={a.label}
              to={a.to}
              className="flex min-w-0 flex-col items-center gap-2 rounded-[14px] border border-line bg-elevated p-2.5 transition-colors hover:border-line-strong"
            >
              <div className="flex size-10 items-center justify-center rounded-full bg-surface text-accent">
                <a.icon size={18} />
              </div>
              <span className="w-full truncate text-center text-[11px] leading-tight text-muted">{a.label}</span>
            </Link>
          ))}
        </div>
      </div>

      <div className="mt-6 rounded-lg border border-line bg-elevated p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-[13px] font-semibold text-fg">
            <LayoutGrid size={16} className="text-accent" /> {t.page.liveMarketTv}
          </div>
          <a
            href="https://www.tradingview.com/symbols/BDXUSD/"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1 rounded-full border border-line-strong bg-surface px-2.5 py-1 text-[10px] text-accent"
          >
            {t.page.viewChart} <ExternalLink size={10} />
          </a>
        </div>
        <div className="mt-4">
          <AdvancedChart />
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
          <TvCredit />
          <div className="text-[10px] text-subtle">{t.page.symbolLine}</div>
        </div>
      </div>

      <div className="mt-6 rounded-lg border border-line bg-elevated p-4">
        <div className="mb-3 flex items-center justify-between">
          <div className="text-[13px] font-semibold text-fg">{t.page.overviewStats}</div>
          <div className="text-[10px] text-subtle">{t.page.chartMeta}</div>
        </div>
        <SymbolOverview />
        <TvCredit className="mt-2" />
      </div>

      <div className="mt-6 rounded-lg border border-line bg-elevated p-4">
        <div className="flex items-center justify-between">
          <div className="text-[13px] font-semibold text-fg">{t.recent}</div>
          <Link to="/app/history" className="text-[11px] text-accent">
            {t.viewAll}
          </Link>
        </div>
        <div className="mt-3 -mx-4">
          {txs.slice(0, 3).map((tx) => (
            <TxRow key={tx.id} tx={tx} />
          ))}
        </div>
      </div>

      <div className="mt-6 rounded-lg border border-line bg-surface p-4">
        <div className="text-[13px] font-semibold text-fg">{t.referralCard}</div>
        <div className="mt-1 text-[11px] text-subtle">{t.referralCardLead}</div>
        <div className="mt-3 flex gap-2">
          <div className="min-w-0 flex-1 truncate rounded-[10px] border border-line-strong bg-elevated px-3 py-2.5 text-[11px] text-muted">
            {referralLink(user)}
          </div>
          <Button
            size="sm"
            className="rounded-[10px]"
            onClick={async () => {
              const link = copyReferral();
              try {
                await copyText(link);
              } catch {
                /* ignore */
              }
              toast(t.linkCopied);
            }}
          >
            <Copy size={14} /> {t.page.copyBtn}
          </Button>
        </div>
      </div>

      {active.length === 0 ? (
        <div className="mt-6 rounded-lg border border-line bg-elevated p-6 text-center">
          <div className="mx-auto flex size-12 items-center justify-center rounded-full bg-surface text-subtle">
            <LayoutGrid size={20} />
          </div>
          <div className="mt-3 font-semibold text-fg">{t.noPlans}</div>
          <div className="mt-1 text-xs text-subtle">{t.noPlansBody}</div>
          <Button className="mt-4" size="sm" onClick={() => navigate({ to: "/app/plans" })}>
            {t.buyPlan}
          </Button>
        </div>
      ) : (
        <div className="mt-6 space-y-3">
          <div className="text-[13px] font-semibold text-fg">{t.activePlans}</div>
          {active.map((p) => {
            const elapsed = Math.min(
              1,
              (Date.now() - p.startedAt) / (p.durationDays * 86_400_000),
            );
            return (
              <div key={p.id} className="rounded-lg border border-line bg-elevated p-4">
                <div className="flex items-center justify-between">
                  <div className="text-xs font-bold tracking-widest">{p.name}</div>
                  <div className="text-[11px] text-accent">
                    +{p.currency === "USD" ? formatUsd(accruedProfit(p)) : formatBdx(accruedProfit(p))} {t.accrued}
                  </div>
                </div>
                <div className="mt-2 text-[11px] text-subtle">
                  {fill(t.page.planMeta, {
                    amount: p.currency === "USD" ? formatUsd(p.amount) : formatBdx(p.amount),
                    pct: Number((p.dailyPct * p.durationDays).toFixed(2)),
                    days: p.durationDays,
                  })}
                </div>
                <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-line">
                  <div
                    className="h-full rounded-full bg-accent"
                    style={{ width: `${Math.max(4, elapsed * 100)}%` }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      )}

    </div>
  );
}

function Stat({
  icon: Icon,
  label,
  value,
  tone,
}: {
  icon: ComponentType<{ size?: number }>;
  label: string;
  value: string;
  tone: string;
}) {
  return (
    <div className="flex items-center gap-3 rounded-md border border-line bg-surface p-3">
      <div className={`flex size-8 items-center justify-center rounded-full bg-line ${tone}`}>
        <Icon size={16} />
      </div>
      <div>
        <div className="text-[10px] text-subtle">{label}</div>
        <div className="text-sm font-semibold text-fg">{value}</div>
      </div>
    </div>
  );
}
