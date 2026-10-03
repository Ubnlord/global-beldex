import { Check } from "lucide-react";
import { PLANS, type Plan } from "@/lib/platform/catalog";
import { Button } from "@/components/ui/button";
import { copy, planMaxLabel } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { cn } from "@/lib/utils";

export function PlanCard({
  plan,
  cta,
  onAction,
}: {
  plan: Plan;
  cta: string;
  onAction: (plan: Plan) => void;
}) {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  return (
    <div className="flex flex-col rounded-xl border border-line bg-elevated p-5">
      <div className="flex items-center gap-2 text-[10px] font-semibold tracking-widest text-subtle">
        {t.page.minFunding}
        <span className="rounded-full bg-surface px-2 py-0.5 text-[11px] font-bold tracking-normal text-fg">
          {plan.min.toLocaleString()} BDX
        </span>
      </div>
      <div className="mt-3 text-sm font-bold tracking-wide text-fg">{plan.name}</div>
      <div className="mt-3 space-y-2 border-t border-line pt-3 text-[12px] text-muted">
        <Line text={`${t.minDepositLabel}: ${plan.min.toLocaleString()} BDX`} />
        <Line text={`${t.maxDepositLabel}: ${planMaxLabel(lang, plan.max)}`} />
        <Line text={`${t.expectedProfit}: ${plan.profit}`} />
        <Line text={`${t.duration}: ${plan.duration}`} />
      </div>
      <Button className="mt-4 w-full" onClick={() => onAction(plan)}>
        {cta}
      </Button>
    </div>
  );
}

function Line({ text }: { text: string }) {
  return (
    <div className="flex items-start gap-2">
      <Check size={14} className="mt-0.5 shrink-0 text-accent" />
      <span>{text}</span>
    </div>
  );
}

function Row({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent?: boolean;
}) {
  return (
    <div className="flex justify-between">
      <span className="text-subtle">{label}</span>
      <span className={accent ? "text-accent" : "text-fg"}>{value}</span>
    </div>
  );
}

export function PlanGrid({
  cta,
  onAction,
}: {
  cta: string;
  onAction: (plan: Plan) => void;
}) {
  return (
    <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {PLANS.map((p) => (
        <PlanCard key={p.id} plan={p} cta={cta} onAction={onAction} />
      ))}
    </div>
  );
}

export function PlanModal({
  plan,
  onClose,
  onConfirm,
  confirmLabel,
}: {
  plan: Plan;
  onClose: () => void;
  onConfirm: () => void;
  confirmLabel: string;
}) {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
      <div className="max-h-[90dvh] w-full max-w-[360px] overflow-y-auto rounded-xl border border-line-strong bg-elevated p-6">
        <div className="flex items-start justify-between">
          <div>
            <div className="text-[11px] font-bold tracking-widest text-accent">{plan.name}</div>
            <div className="mt-1 text-xl font-bold text-fg">{plan.min.toLocaleString()} BDX</div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="flex size-8 items-center justify-center rounded-full bg-surface text-subtle"
          >
            ×
          </button>
        </div>
        <div className="mt-5 space-y-3 text-[13px]">
          <Row label={t.maxDepositLabel} value={planMaxLabel(lang, plan.max)} />
          <Row label={t.expectedProfit} value={plan.profit} accent />
          <Row label={t.duration} value={plan.duration} />
        </div>
        <div className="mt-6 flex gap-2">
          <Button variant="secondary" className="flex-1" onClick={onClose}>
            {t.close}
          </Button>
          <Button className="flex-1" onClick={onConfirm}>
            {confirmLabel}
          </Button>
        </div>
        <p className="mt-3 text-center text-[10px] text-subtle">
          {t.page.eduDemo}
        </p>
      </div>
    </div>
  );
}

export function TvCredit({ className }: { className?: string }) {
  const lang = usePlatform((s) => s.lang);
  const p = copy[lang].page;
  return (
    <p className={cn("text-[10px] text-subtle", className)}>
      {p.liveFromTv.split("·")[0]}·{" "}
      <a
        href="https://www.tradingview.com/symbols/BDXUSD/"
        target="_blank"
        rel="noopener noreferrer"
        className="text-accent hover:underline"
      >
        {p.trackOnTv}
      </a>
    </p>
  );
}
