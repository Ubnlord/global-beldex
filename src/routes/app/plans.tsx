import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { TickerTape } from "@/components/market/tradingview";
import { toast, toastError } from "@/components/layout/toast";
import { PlanGrid } from "@/components/platform/plan-card";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import type { Plan } from "@/lib/platform/catalog";
import { projectedReturn } from "@/lib/platform/catalog";
import { copy, fill } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { bdxToUsd, formatBdx, formatUsd } from "@/lib/utils";

export const Route = createFileRoute("/app/plans")({ component: PlansPage });

function PlansPage() {
  const navigate = useNavigate();
  const available = usePlatform((s) => s.available);
  const activePlans = usePlatform((s) => s.plans);
  const buyPlan = usePlatform((s) => s.buyPlan);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [selected, setSelected] = useState<Plan | null>(null);
  const [amount, setAmount] = useState("");

  const confirm = async () => {
    if (!selected) return;
    const n = parseFloat(amount) || selected.min;
    const err = await buyPlan(selected, n);
    if (err) {
      toastError(err);
      return;
    }
    toast(fill(t.activated, { name: selected.name }));
    setSelected(null);
    void navigate({ to: "/app" });
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4 md:max-w-[960px]">
      <TickerTape />
      <h2 className="mt-4 text-xl font-bold">{t.plansTitle}</h2>
      <p className="mt-1 text-xs text-subtle">{fill(t.plansLead, { amount: formatUsd(available) })}</p>
      {activePlans.length > 0 && (
        <section className="mt-5 space-y-3">
          <div>
            <h3 className="text-sm font-bold">{t.activePlans}</h3>
            <p className="mt-1 text-xs text-subtle">
              Your daily interest is calculated from the server-backed investment record.
            </p>
          </div>
          {activePlans.map((plan) => (
            <InvestmentMetrics key={plan.id} plan={plan} />
          ))}
        </section>
      )}

      <PlanGrid
        cta={t.buyPlan}
        onAction={(p) => {
          setSelected(p);
          setAmount(String(p.min));
          toast(fill(t.selected, { name: p.name }));
        }}
      />
      {selected && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
          <div className="w-full max-w-[360px] rounded-xl border border-line-strong bg-elevated p-6">
            <div className="text-[11px] font-bold tracking-widest text-accent">
              {selected.name}
            </div>
            <div className="mt-1 text-xl font-bold">{formatBdx(selected.min)} min</div>
            <div className="mt-1 text-xs font-semibold text-accent">≈ {formatUsd(bdxToUsd(selected.min), 3)} USD</div>
            <p className="mt-2 text-[13px] text-subtle">
              {selected.profit} · {selected.duration} · max {selected.max}
            </p>
            <div className="mt-4">
              <FieldLabel>{t.lockAmount}</FieldLabel>
              <Input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
            </div>
            <Projection amount={parseFloat(amount) || selected.min} plan={selected} />
            <div className="mt-6 flex gap-2">
              <Button variant="secondary" className="flex-1" onClick={() => setSelected(null)}>
                {t.close}
              </Button>
              <Button className="flex-1" onClick={confirm}>
                {t.confirm}
              </Button>
            </div>
            <p className="mt-3 text-center text-[10px] text-subtle">
              Live market data from TradingView
            </p>
          </div>
        </div>
      )}
    </div>
  );
}

function Projection({ amount, plan }: { amount: number; plan: Plan }) {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const { profit, total } = projectedReturn(amount, plan);
  return (
    <div className="mt-3 rounded-md border border-line bg-surface px-3 py-2 text-[12px] text-subtle">
      {t.heldTerm} <span className="text-accent">+{formatUsd(profit)}</span> {t.profitWord} ·{" "}
      {formatUsd(total)} {t.returned}
    </div>
  );
}


function InvestmentMetrics({ plan }: { plan: import("@/lib/platform/store").ActivePlan }) {
  const now = Date.now();
  const dailyInterest = plan.amount * (plan.dailyPct / 100);
  const totalInterest = plan.creditedProfit ?? 0;
  const endAt = plan.startedAt + plan.durationDays * 86_400_000;
  const remainingMs = Math.max(0, endAt - now);
  const daysRemaining = Math.ceil(remainingMs / 86_400_000);
  const nextRun = useMemo(() => {
    const d = new Date(now);
    d.setUTCHours(24, 0, 0, 0);
    return d;
  }, [now]);

  const nextInterest = plan.status === "completed"
    ? "Completed"
    : nextRun.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });

  const metrics = [
    { label: "Today's Interest", value: `+${formatBdx(dailyInterest)} · ${formatUsd(bdxToUsd(dailyInterest), 3)}` },
    { label: "Total Interest Earned", value: `+${formatBdx(totalInterest)} · ${formatUsd(bdxToUsd(totalInterest), 3)}` },
    { label: "Next Interest", value: nextInterest },
    { label: "Days Remaining", value: String(daysRemaining) },
  ];

  return (
    <div className="rounded-xl border border-line bg-surface p-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <div className="text-[11px] font-bold tracking-widest text-accent">{plan.name}</div>
          <div className="mt-1 text-sm font-semibold">{formatBdx(plan.amount)} principal</div>
          <div className="mt-0.5 text-xs text-subtle">≈ {formatUsd(bdxToUsd(plan.amount), 3)} USD</div>
        </div>
        <span className="rounded-full border border-line px-2 py-1 text-[10px] font-semibold uppercase text-subtle">
          {plan.status}
        </span>
      </div>
      <div className="mt-4 grid grid-cols-2 gap-2">
        {metrics.map((metric) => (
          <div key={metric.label} className="rounded-lg border border-line bg-bg/60 p-3">
            <div className="text-[10px] uppercase tracking-wide text-subtle">{metric.label}</div>
            <div className="mt-1 text-sm font-bold text-accent">{metric.value}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
