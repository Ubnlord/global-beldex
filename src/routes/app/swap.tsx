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
import { BDX_USD_RATE, formatBdx, formatUsd } from "@/lib/utils";

export const Route = createFileRoute("/app/swap")({ component: SwapPage });

function SwapPage() {
  const bdx = usePlatform((s) => s.bdx);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const { usd } = useBeldexQuote();
  const rate = usd && usd > 0 ? usd : BDX_USD_RATE;
  const [from, setFrom] = useState<"USD" | "BDX">("BDX");
  const [amount, setAmount] = useState("");
  const to = from === "USD" ? "BDX" : "USD";
  const n = parseFloat(amount) || 0;
  const out = useMemo(() => {
    if (!rate) return 0;
    return from === "USD" ? n / rate : n * rate;
  }, [from, n, rate]);
  const hasBdxFunding = n <= bdx;

  const flip = () => {
    toastError("Swaps are temporarily unavailable while BDX-only accounting is being completed.");
  };

  const submit = async () => {
    toastError("USD/BDX swaps are temporarily disabled until the swap API supports BDX-only accounting.");
    return;
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
          {`Available BDX: ${formatBdx(bdx)} · Estimated BDX value: ${formatUsd(bdx * rate, 3)}`}
        </div>
        <Button className="mt-6 w-full" onClick={submit} disabled={!rate || n <= 0}>
          Swaps temporarily unavailable
        </Button>
        <p className="mt-2 text-[11px] text-subtle">Account and investment balances use BDX. USD is only used as a deposit/withdrawal entry amount. Swaps will be re-enabled after the server-side swap accounting is converted to BDX.</p>
      </div>
    </div>
  );
}
