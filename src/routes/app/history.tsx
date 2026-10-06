import { createFileRoute } from "@tanstack/react-router";
import { History } from "lucide-react";
import { useEffect, useState } from "react";
import { TickerTape } from "@/components/market/tradingview";
import { TxRow } from "@/components/platform/tx-row";
import { copy, fill } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/app/history")({ component: HistoryPage });

const TABS = ["deposit", "withdraw", "others"] as const;

function HistoryPage() {
  const txs = usePlatform((s) => s.txs);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [tab, setTab] = useState<(typeof TABS)[number]>("deposit");
  const refreshTransactions = usePlatform((s) => s.refreshTransactions);

  useEffect(() => {
    let active = true;
    const timer = window.setInterval(() => {
      void refresh();
    }, 2500);

    const refresh = async () => {
      if (!active || document.visibilityState !== "visible") return;
      await refreshTransactions();
    };

    void refresh();


    const onVisible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onVisible);

    return () => {
      active = false;
      if (timer) window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onVisible);
    };
  }, [refreshTransactions]);
  const filtered =
    tab === "others"
      ? txs.filter((z) => z.type !== "deposit" && z.type !== "withdraw")
      : txs.filter((z) => z.type === tab);

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <TickerTape />
      <h2 className="mt-4 text-xl font-bold">{t.historyTitle}</h2>
      <div className="mt-4 flex w-fit gap-2 rounded-full border border-line bg-surface p-1">
        {TABS.map((id) => (
          <button
            key={id}
            type="button"
            onClick={() => setTab(id)}
            className={cn(
              "rounded-full px-5 py-2 text-xs font-medium capitalize transition-colors",
              tab === id ? "bg-accent text-accent-fg" : "text-subtle",
            )}
          >
            {id === "others" ? t.others : t[id]}
          </button>
        ))}
      </div>
      <div className="mt-6">
        {filtered.length === 0 ? (
          <div className="rounded-lg border border-line bg-elevated p-10 text-center">
            <div className="mx-auto flex size-14 items-center justify-center rounded-full bg-surface text-subtle">
              <History size={22} />
            </div>
            <div className="mt-4 font-semibold text-fg">{t.noTx}</div>
            <div className="mt-1 text-xs text-subtle">
              {fill(t.noTxBody, { tab: tab === "others" ? t.others : t[tab] })}
            </div>
          </div>
        ) : (
          <div className="divide-y divide-line overflow-hidden rounded-lg border border-line bg-elevated">
            {filtered.map((z) => (
              <TxRow key={z.id} tx={z} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
