import { createServerFn } from "@tanstack/react-start";

export type QuoteBook = Record<string, { usd: number; change: number }>;

async function mexc(symbol: string) {
  const res = await fetch(`https://api.mexc.com/api/v3/ticker/24hr?symbol=${symbol}`, {
    headers: { accept: "application/json" },
  });
  if (!res.ok) return null;
  const row = (await res.json()) as { lastPrice?: string; priceChangePercent?: string };
  const usd = Number(row.lastPrice);
  const ratio = Number(row.priceChangePercent);
  if (!Number.isFinite(usd) || usd <= 0) return null;
  return { usd, change: Number.isFinite(ratio) ? ratio * 100 : 0 };
}

async function krakenMajors(): Promise<QuoteBook> {
  const res = await fetch("https://api.kraken.com/0/public/Ticker?pair=XBTUSD,ETHUSD", {
    headers: { accept: "application/json" },
  });
  if (!res.ok) return {};
  const data = (await res.json()) as {
    result?: Record<string, { c?: string[]; o?: string }>;
  };
  const book: QuoteBook = {};
  const btc = data.result?.XXBTZUSD;
  const eth = data.result?.XETHZUSD;
  const pack = (row?: { c?: string[]; o?: string }) => {
    const last = Number(row?.c?.[0]);
    const open = Number(row?.o);
    if (!Number.isFinite(last) || last <= 0) return null;
    const change = Number.isFinite(open) && open > 0 ? ((last - open) / open) * 100 : 0;
    return { usd: last, change };
  };
  const b = pack(btc);
  const e = pack(eth);
  if (b) book.bitcoin = b;
  if (e) book.ethereum = e;
  return book;
}

async function kucoinBeldex() {
  const res = await fetch("https://api.kucoin.com/api/v1/market/stats?symbol=BDX-USDT", {
    headers: { accept: "application/json" },
  });
  if (!res.ok) return null;
  const data = (await res.json()) as { data?: { last?: string; changeRate?: string } };
  const usd = Number(data.data?.last);
  const rate = Number(data.data?.changeRate);
  if (!Number.isFinite(usd) || usd <= 0) return null;
  return { usd, change: Number.isFinite(rate) ? rate * 100 : 0 };
}

export const fetchQuotes = createServerFn({ method: "GET" }).handler(async (): Promise<QuoteBook> => {
  const [btc, eth, bdx] = await Promise.all([mexc("BTCUSDT"), mexc("ETHUSDT"), mexc("BDXUSDT")]);
  const book: QuoteBook = {};
  if (btc) book.bitcoin = btc;
  if (eth) book.ethereum = eth;
  if (bdx) book.beldex = bdx;
  if (!book.bitcoin || !book.ethereum) {
    const extra = await krakenMajors();
    book.bitcoin ??= extra.bitcoin;
    book.ethereum ??= extra.ethereum;
  }
  if (!book.beldex) {
    const extra = await kucoinBeldex();
    if (extra) book.beldex = extra;
  }
  return book;
});

export type BeldexDetail = {
  usd: number | null;
  high: number | null;
  low: number | null;
  marketCap: number | null;
  volume: number | null;
  rank: number | null;
  changes: Record<string, number | null>;
};

export const fetchBeldexDetail = createServerFn({ method: "GET" }).handler(async (): Promise<BeldexDetail> => {
  const empty: BeldexDetail = {
    usd: null,
    high: null,
    low: null,
    marketCap: null,
    volume: null,
    rank: null,
    changes: {},
  };
  try {
    const [coinRes, chartRes] = await Promise.all([
      fetch(
        "https://api.coingecko.com/api/v3/coins/beldex?localization=false&tickers=false&community_data=false&developer_data=false&sparkline=false",
        { headers: { accept: "application/json" } },
      ),
      fetch("https://api.coingecko.com/api/v3/coins/beldex/market_chart?vs_currency=usd&days=365", {
        headers: { accept: "application/json" },
      }),
    ]);
    if (!coinRes.ok) {
      const stats = await fetch("https://api.kucoin.com/api/v1/market/stats?symbol=BDX-USDT", {
        headers: { accept: "application/json" },
      });
      if (!stats.ok) return empty;
      const body = (await stats.json()) as {
        data?: { last?: string; high?: string; low?: string; volValue?: string; changeRate?: string };
      };
      const row = body.data;
      const usd = Number(row?.last);
      const high = Number(row?.high);
      const low = Number(row?.low);
      const volume = Number(row?.volValue);
      const rate = Number(row?.changeRate);
      return {
        usd: Number.isFinite(usd) && usd > 0 ? usd : null,
        high: Number.isFinite(high) ? high : null,
        low: Number.isFinite(low) ? low : null,
        marketCap: null,
        volume: Number.isFinite(volume) ? volume : null,
        rank: null,
        changes: {
          "24h": Number.isFinite(rate) ? rate * 100 : null,
          "7d": null,
          "1m": null,
          "3m": null,
          "6m": null,
          YTD: null,
          "1y": null,
        },
      };
    }
    const coin = (await coinRes.json()) as {
      market_cap_rank?: number;
      market_data?: {
        current_price?: { usd?: number };
        high_24h?: { usd?: number };
        low_24h?: { usd?: number };
        market_cap?: { usd?: number };
        total_volume?: { usd?: number };
      };
    };
    const md = coin.market_data;
    const changes: Record<string, number | null> = {
      "24h": null,
      "7d": null,
      "1m": null,
      "3m": null,
      "6m": null,
      YTD: null,
      "1y": null,
    };
    if (chartRes.ok) {
      const chart = (await chartRes.json()) as { prices?: [number, number][] };
      const prices = chart.prices ?? [];
      const last = prices[prices.length - 1];
      const at = (days: number) => {
        if (!last) return null;
        const target = last[0] - days * 86_400_000;
        let pick = prices[0];
        for (const row of prices) {
          if (row[0] <= target) pick = row;
        }
        if (!pick || !pick[1]) return null;
        return ((last[1] - pick[1]) / pick[1]) * 100;
      };
      const yearStart = last ? Date.parse(`${new Date(last[0]).getUTCFullYear()}-01-01T00:00:00Z`) : 0;
      const ytd = () => {
        if (!last) return null;
        let pick = prices[0];
        for (const row of prices) {
          if (row[0] <= yearStart) pick = row;
        }
        if (!pick || !pick[1]) return null;
        return ((last[1] - pick[1]) / pick[1]) * 100;
      };
      changes["24h"] = at(1);
      changes["7d"] = at(7);
      changes["1m"] = at(30);
      changes["3m"] = at(90);
      changes["6m"] = at(180);
      changes.YTD = ytd();
      changes["1y"] = at(365);
    }
    return {
      usd: md?.current_price?.usd ?? null,
      high: md?.high_24h?.usd ?? null,
      low: md?.low_24h?.usd ?? null,
      marketCap: md?.market_cap?.usd ?? null,
      volume: md?.total_volume?.usd ?? null,
      rank: coin.market_cap_rank ?? null,
      changes,
    };
  } catch {
    return empty;
  }
});
