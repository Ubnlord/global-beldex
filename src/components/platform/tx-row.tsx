import { ArrowDownToLine, ArrowUpFromLine, Gift, LayoutGrid, Repeat, Users } from "lucide-react";
import { formatUsd } from "@/lib/utils";
import type { Transaction } from "@/lib/platform/store";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { cn } from "@/lib/utils";

const ICONS = {
  deposit: ArrowDownToLine,
  withdraw: ArrowUpFromLine,
  bonus: Gift,
  plan: LayoutGrid,
  swap: Repeat,
  referral: Users,
};

export function TxRow({ tx }: { tx: Transaction }) {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const Icon = ICONS[tx.type] ?? Gift;
  const tone =
    tx.type === "withdraw"
      ? "bg-danger/15 text-danger"
      : tx.type === "bonus" || tx.type === "referral"
        ? "bg-warn/15 text-warn"
        : "bg-accent/15 text-accent";
  const amountTone = tx.type === "withdraw" ? "text-danger" : "text-accent";
  const sign = tx.type === "withdraw" || tx.type === "plan" ? "−" : "+";

  return (
    <div className="flex items-center justify-between border-b border-line px-4 py-3 last:border-0">
      <div className="flex items-center gap-3">
        <div className={cn("flex size-9 items-center justify-center rounded-full", tone)}>
          <Icon size={14} />
        </div>
        <div>
          <div className="text-[13px] text-fg">
            {t.tx[tx.type]} · {tx.method}
          </div>
          <div className="text-[11px] text-subtle">{tx.date}</div>
        </div>
      </div>
      <div className="text-right">
        <div className={cn("text-[13px] font-semibold", amountTone)}>
          {sign}
          {formatUsd(tx.amount)}
        </div>
        <div
          className={cn(
            "inline-block rounded-full px-2 py-0.5 text-[10px]",
            tx.status === "completed" ? "bg-accent/20 text-accent" : "bg-warn/20 text-warn",
          )}
        >
          {tx.status === "completed" ? t.completed : tx.status === "failed" ? t.failed : t.pending}
        </div>
      </div>
    </div>
  );
}
