import { useEffect, useState } from "react";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { CoinLogo } from "@/components/market/coin-logo";
import { cn } from "@/lib/utils";
import { useBeldexQuote } from "@/components/market/live-price";

const RANGES = ["24h", "7d", "1m", "3m", "6m", "YTD", "1y"] as const;

type Detail = {
  usd: number | null;
  high: number | null;
  low: number | null;
  marketCap: number | null;
  volume: number | null;
  rank: number | null;
  changes: Record<string, number | null>;
};

const EMPTY: Detail = {
  usd: null,
  high: null,
  low: null,
  marketCap: null,
  volume: null,
  rank: null,
  changes: {},
};

async function getJson<T>(url: string, timeoutMs = 8000): Promise<T> {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      headers: { accept: "application/json" },
      cache: "no-store",
      signal: controller.signal,
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return (await res.json()) as T;
  } finally {
    window.clearTimeout(timeout);
  }
}

async function fetchBeldexDetail(): Promise<Detail> {
  try {
    const [coinRes, chartRes] = await Promise.allSettled([
      getJson<{
        market_cap_rank?: number;
        market_data?: {
          current_price?: { usd?: number };
          high_24h?: { usd?: number };
          low_24h?: { usd?: number };
          market_cap?: { usd?: number };
          total_volume?: { usd?: number };
          price_change_percentage_24h?: number;
          price_change_percentage_7d?: number;
          price_change_percentage_30d?: number;
          price_change_percentage_90d?: number;
          price_change_percentage_180d?: number;
          price_change_percentage_1y?: number;
        };
      }>(
        "https://api.coingecko.com/api/v3/coins/beldex?localization=false&tickers=false&community_data=false&developer_data=false&sparkline=false&price_change_percentage=24h,7d,30d,90d,180d,1y",
      ),
      getJson<{ prices?: [number, number][] }>(
        "https://api.coingecko.com/api/v3/coins/beldex/market_chart?vs_currency=usd&days=365",
      ),
    ]);

    if (coinRes.status === "fulfilled") {
      const md = coinRes.value.market_data;
      const changes: Record<string, number | null> = {
        "24h": md?.price_change_percentage_24h ?? null,
        "7d": md?.price_change_percentage_7d ?? null,
        "1m": md?.price_change_percentage_30d ?? null,
        "3m": md?.price_change_percentage_90d ?? null,
        "6m": md?.price_change_percentage_180d ?? null,
        "1y": md?.price_change_percentage_1y ?? null,
        YTD: null,
      };

      if (chartRes.status === "fulfilled") {
        const prices = chartRes.value.prices ?? [];
        const last = prices[prices.length - 1];
        if (last) {
          const yearStart = Date.parse(
            `${new Date(last[0]).getUTCFullYear()}-01-01T00:00:00Z`,
          );
          let start = prices[0];
          for (const row of prices) {
            if (row[0] <= yearStart) start = row;
          }
          if (start?.[1] > 0) {
            changes.YTD = ((last[1] - start[1]) / start[1]) * 100;
          }
        }
      }

      return {
        usd: md?.current_price?.usd ?? null,
        high: md?.high_24h?.usd ?? null,
        low: md?.low_24h?.usd ?? null,
        marketCap: md?.market_cap?.usd ?? null,
        volume: md?.total_volume?.usd ?? null,
        rank: coinRes.value.market_cap_rank ?? null,
        changes,
      };
    }

    const fallback = await getJson<{
      data?: {
        last?: string;
        high?: string;
        low?: string;
        volValue?: string;
        changeRate?: string;
      };
    }>("https://api.kucoin.com/api/v1/market/stats?symbol=BDX-USDT");

    const row = fallback.data;
    const usd = Number(row?.last);
    const high = Number(row?.high);
    const low = Number(row?.low);
    const volume = Number(row?.volValue);
    const change = Number(row?.changeRate) * 100;

    return {
      ...EMPTY,
      usd: Number.isFinite(usd) && usd > 0 ? usd : null,
      high: Number.isFinite(high) && high > 0 ? high : null,
      low: Number.isFinite(low) && low > 0 ? low : null,
      volume: Number.isFinite(volume) ? volume : null,
      changes: {
        "24h": Number.isFinite(change) ? change : null,
      },
    };
  } catch {
    return EMPTY;
  }
}

function money(n: number | null, digits = 5) {
  if (n == null || !Number.isFinite(n)) return "—";
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

function compact(n: number | null) {
  if (n == null || !Number.isFinite(n)) return "—";
  return n.toLocaleString("en-US", { maximumFractionDigits: 0 });
}

function pct(n: number | null) {
  if (n == null || !Number.isFinite(n)) return "—";
  return `${n >= 0 ? "+" : ""}${n.toFixed(1)}%`;
}

export function HomeBeldexStats() {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [detail, setDetail] = useState<Detail>(EMPTY);
  const [range, setRange] = useState<(typeof RANGES)[number]>("24h");
  const live = useBeldexQuote();

  useEffect(() => {
    let stop = false;
    const load = () => {
      void fetchBeldexDetail().then((row) => {
        if (!stop) setDetail(row);
      });
    };
    load();
    const id = window.setInterval(load, 60_000);
    return () => {
      stop = true;
      window.clearInterval(id);
    };
  }, []);

  // Always use the protected live quote for the headline BDX price and 24h change.
  // The detail endpoint is supplementary and can be rate-limited independently.
  const livePrice = live.usd ?? detail.usd;
  const live24h = live.change24h ?? detail.changes["24h"] ?? null;
  const change = range === "24h" ? live24h : detail.changes[range] ?? null;
  const up = (change ?? 0) >= 0;

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-line bg-surface p-4">
        <div className="flex items-center gap-3">
          <CoinLogo coin="beldex" size={40} />
          <div>
            <div className="text-sm font-semibold">Beldex</div>
            <div className="text-[11px] text-subtle">BDX/USD</div>
          </div>
          <div className="ml-auto text-right">
            <div className="text-lg font-bold tabular">{money(livePrice)}</div>
            <div className={cn("text-xs font-semibold tabular", up ? "text-accent" : "text-danger")}>
              {pct(live24h)}
            </div>
          </div>
        </div>

        <div className="mt-4 grid grid-cols-2 gap-3 text-[12px]">
          <Stat label="Market Cap Rank" value={detail.rank ? `#${detail.rank}` : "—"} />
          <Stat label="Market Cap" value={detail.marketCap ? `$${compact(detail.marketCap)}` : "—"} />
          <Stat label="24h Volume" value={detail.volume ? `$${compact(detail.volume)}` : "—"} />
          <Stat label="24h High/Low" value={`${money(detail.high)} / ${money(detail.low)}`} />
        </div>

        <div className="mt-3 text-[10px] text-subtle">
          Live market data · chart powered by TradingView
        </div>
      </div>

      <div className="rounded-xl border border-line bg-surface p-4">
        <div className="text-sm font-semibold">{t.page.compareTitle}</div>
        <div className="mt-3 flex gap-1 overflow-x-auto pb-1">
          {RANGES.map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => setRange(item)}
              className={cn(
                "shrink-0 rounded-full px-3 py-1.5 text-[11px] font-semibold",
                range === item ? "bg-accent text-accent-fg" : "bg-elevated text-muted",
              )}
            >
              {item}
            </button>
          ))}
        </div>

        <div className="mt-4 flex items-center justify-between rounded-lg border border-line bg-elevated px-3 py-3">
          <div className="flex items-center gap-2">
            <CoinLogo coin="beldex" size={28} />
            <div>
              <div className="text-sm font-semibold">BDX</div>
              <div className="text-[11px] text-subtle">Beldex</div>
            </div>
          </div>
          <div className="text-right">
            <div className="font-semibold tabular">{money(detail.usd)}</div>
            <div className={cn("text-xs font-semibold tabular", up ? "text-accent" : "text-danger")}>
              {pct(change)}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-line bg-elevated px-3 py-2">
      <div className="text-[10px] text-subtle">{label}</div>
      <div className="mt-0.5 break-words text-[12px] font-semibold tabular text-fg">{value}</div>
    </div>
  );
}
