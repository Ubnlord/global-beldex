import { createFileRoute } from "@tanstack/react-router";
import { ArrowDownUp } from "lucide-react";
import { useMemo, useState } from "react";
import { TickerTape } from "@/components/market/tradingview";
import { toast, toastError } from "@/components/layout/toast";
import { CoinLogo } from "@/components/market/coin-logo";
import { BdxConverter, useBeldexQuote } from "@/components/market/live-price";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { copy, fill } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { formatUsd } from "@/lib/utils";

export const Route = createFileRoute("/app/swap")({ component: SwapPage });

function SwapPage() {
  const available = usePlatform((s) => s.available);
  const bdx = usePlatform((s) => s.bdx);
  const swap = usePlatform((s) => s.swap);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const { usd } = useBeldexQuote();
  const rate = usd && usd > 0 ? usd : null;
  const [from, setFrom] = useState<"USD" | "BDX">("USD");
  const [amount, setAmount] = useState("");
  const to = from === "USD" ? "BDX" : "USD";
  const n = parseFloat(amount) || 0;
  const out = useMemo(() => {
    if (!rate) return 0;
    return from === "USD" ? n / rate : n * rate;
  }, [from, n, rate]);

  const flip = () => {
    setFrom(to);
    setAmount("");
  };

  const submit = async () => {
    if (!rate) {
      toastError(t.err.BAD_RATE);
      return;
    }
    const err = await swap(from, to, n, rate);
    if (err) {
      toastError(err);
      return;
    }
    toast(t.swapped);
    setAmount("");
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <TickerTape />
      <div className="mt-4">
        <BdxConverter />
      </div>
      <h2 className="mt-4 text-xl font-bold">{t.swapTitle}</h2>
      <p className="mt-1 text-xs text-subtle">{t.swapLead}</p>
      <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
        <div className="text-[11px] text-muted">{t.rate}</div>
        <div className="flex items-center gap-2 text-lg font-bold tabular">
          <CoinLogo coin="beldex" size={22} />
          1 BDX = {rate ? formatUsd(rate, 5) : t.err.BAD_RATE}
        </div>
        <div className="mt-5">
          <FieldLabel>
            <span className="inline-flex items-center gap-1.5">
              {from === "BDX" ? <CoinLogo coin="beldex" size={16} /> : null}
              {t.from} {from}
            </span>
          </FieldLabel>
          <Input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
          />
        </div>
        <button
          type="button"
          onClick={flip}
          className="mx-auto my-3 flex size-10 items-center justify-center rounded-full border border-line bg-surface text-accent"
          aria-label="Flip assets"
        >
          <ArrowDownUp size={16} />
        </button>
        <div>
          <FieldLabel>
            <span className="inline-flex items-center gap-1.5">
              {to === "BDX" ? <CoinLogo coin="beldex" size={16} /> : null}
              {t.to} {to}
            </span>
          </FieldLabel>
          <div className="mt-1 rounded-md border border-line-strong bg-surface px-4 py-3 text-sm tabular">
            {rate ? (out ? out.toFixed(to === "USD" ? 2 : 4) : "0.00") : t.err.BAD_RATE}
          </div>
        </div>
        <div className="mt-2 text-[11px] text-subtle">
          {fill(t.usdAvail, { usd: formatUsd(available), bdx: bdx.toFixed(4) })}
        </div>
        <Button className="mt-6 w-full" onClick={submit} disabled={!rate || n <= 0}>
          {t.swapNow}
        </Button>
      </div>
    </div>
  );
}
