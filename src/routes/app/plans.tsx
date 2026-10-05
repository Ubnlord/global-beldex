import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { TickerTape } from "@/components/market/tradingview";
import { toast, toastError } from "@/components/layout/toast";
import { PlanGrid } from "@/components/platform/plan-card";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import type { Plan } from "@/lib/platform/catalog";
import { projectedReturn } from "@/lib/platform/catalog";
import { copy, fill } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { formatUsd } from "@/lib/utils";

export const Route = createFileRoute("/app/plans")({ component: PlansPage });

function PlansPage() {
  const navigate = useNavigate();
  const available = usePlatform((s) => s.available);
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
            <div className="mt-1 text-xl font-bold">{selected.min.toLocaleString()} BDX min</div>
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
