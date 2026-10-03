import { createFileRoute } from "@tanstack/react-router";
import { ExternalLink } from "lucide-react";
import {
  AdvancedChart,
  MiniChart,
  SymbolOverview,
  TickerTape,
} from "@/components/market/tradingview";
import { LiveBadge, PriceChip, BdxConverter } from "@/components/market/live-price";
import { TvCredit } from "@/components/platform/plan-card";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";

export const Route = createFileRoute("/app/markets")({ component: MarketsPage });

function MarketsPage() {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4 md:max-w-[960px]">
      <TickerTape />
      <div className="mt-4 flex items-start justify-between gap-3">
        <div>
          <h2 className="text-xl font-bold">{t.markets}</h2>
          <LiveBadge className="mt-2" />
        </div>
        <PriceChip />
      </div>
      <div className="mt-4">
        <BdxConverter />
      </div>
      <div className="mt-6 rounded-lg border border-line bg-elevated p-4">
        <div className="mb-3 flex items-center justify-between">
          <div className="text-[13px] font-semibold">{t.page.liveMarketTv}</div>
          <a
            href="https://www.tradingview.com/symbols/BDXUSD/"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1 text-[10px] text-accent"
          >
            {t.page.trackBdx} <ExternalLink size={10} />
          </a>
        </div>
        <AdvancedChart />
        <TvCredit className="mt-2" />
      </div>
      <div className="mt-4 rounded-lg border border-line bg-elevated p-4">
        <div className="mb-3 text-[13px] font-semibold">{t.page.overviewStats}</div>
        <SymbolOverview />
      </div>
      <div className="mt-4 rounded-lg border border-line bg-elevated p-4">
        <div className="mb-3 text-[13px] font-semibold">{t.page.intraday}</div>
        <MiniChart />
      </div>
    </div>
  );
}
