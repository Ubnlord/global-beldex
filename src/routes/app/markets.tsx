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
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <section id="forex" className="scroll-mt-24 rounded-lg border border-line bg-elevated p-4">
          <div className="text-xs font-semibold tracking-widest text-accent">FOREX</div>
          <h3 className="mt-1 text-base font-bold">Foreign Exchange Markets</h3>
          <p className="mt-2 text-[12px] leading-5 text-subtle">
            Explore the foreign-exchange market and commonly followed currency pairs such as
            EUR/USD, GBP/USD, and USD/JPY. Market availability, pricing, leverage, and trading
            conditions depend on your jurisdiction and account eligibility.
          </p>
          <div className="mt-3 flex flex-wrap gap-2 text-[11px]">
            {["EUR/USD", "GBP/USD", "USD/JPY"].map((pair) => (
              <span key={pair} className="rounded-full border border-line px-2 py-1 text-muted">
                {pair}
              </span>
            ))}
          </div>
        </section>

        <section id="cryptos" className="scroll-mt-24 rounded-lg border border-line bg-elevated p-4">
          <div className="text-xs font-semibold tracking-widest text-accent">CRYPTOS</div>
          <h3 className="mt-1 text-base font-bold">Crypto Markets</h3>
          <p className="mt-2 text-[12px] leading-5 text-subtle">
            View crypto-market information and the BDX market tools available on Global Beldex.
            The live BDX price, converter, chart, and market overview below are designed to show
            current market information when a live source is available.
          </p>
          <a
            href="https://www.tradingview.com/symbols/BDXUSD/"
            target="_blank"
            rel="noopener noreferrer"
            className="mt-3 inline-flex text-[11px] font-semibold text-accent hover:underline"
          >
            Open BDX/USD chart <ExternalLink size={11} className="ml-1" />
          </a>
        </section>
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
