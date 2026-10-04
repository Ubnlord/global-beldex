export type QuoteBook = Record<string, { usd: number; change: number }>;

type CoinGeckoResponse = Record<
  string,
  { usd?: number; usd_24h_change?: number }
>;

type FetchOptions = {
  timeoutMs?: number;
};

async function getJson<T>(url: string, options: FetchOptions = {}): Promise<T> {
  const controller = new AbortController();
  const timeout = window.setTimeout(
    () => controller.abort(),
    options.timeoutMs ?? 6500,
  );

  try {
    const res = await fetch(url, {
      headers: { accept: "application/json" },
      cache: "no-store",
      signal: controller.signal,
    });
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    return (await res.json()) as T;
  } finally {
    window.clearTimeout(timeout);
  }
}

function validQuote(usd: unknown, change: unknown) {
  const price = Number(usd);
  const delta = Number(change);
  if (!Number.isFinite(price) || price <= 0) return null;
  return {
    usd: price,
    change: Number.isFinite(delta) ? delta : 0,
  };
}

async function coinGecko(): Promise<QuoteBook> {
  const data = await getJson<CoinGeckoResponse>(
    "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,beldex&vs_currencies=usd&include_24hr_change=true",
  );

  const book: QuoteBook = {};
  const add = (id: string, key: string) => {
    const row = data[id];
    const quote = validQuote(row?.usd, row?.usd_24h_change);
    if (quote) book[key] = quote;
  };

  add("bitcoin", "bitcoin");
  add("ethereum", "ethereum");
  add("beldex", "beldex");
  return book;
}

async function kucoinBeldex(): Promise<QuoteBook> {
  const data = await getJson<{
    data?: { last?: string; changeRate?: string };
  }>("https://api.kucoin.com/api/v1/market/stats?symbol=BDX-USDT");

  const quote = validQuote(
    data.data?.last,
    Number(data.data?.changeRate) * 100,
  );

  return quote ? { beldex: quote } : {};
}

async function dexScreenerBeldex(): Promise<QuoteBook> {
  const data = await getJson<{
    pairs?: Array<{
      baseToken?: { symbol?: string };
      quoteToken?: { symbol?: string };
      priceUsd?: string | null;
      priceChange?: { h24?: number };
      liquidity?: { usd?: number | null };
    }>;
  }>("https://api.dexscreener.com/latest/dex/search?q=BDX");

  const candidates = (data.pairs ?? [])
    .filter((pair) => pair.baseToken?.symbol?.toUpperCase() === "BDX")
    .map((pair) => ({
      quote: validQuote(pair.priceUsd, pair.priceChange?.h24),
      liquidity: Number(pair.liquidity?.usd) || 0,
    }))
    .filter(
      (row): row is { quote: { usd: number; change: number }; liquidity: number } =>
        Boolean(row.quote),
    )
    .sort((a, b) => b.liquidity - a.liquidity);

  return candidates[0] ? { beldex: candidates[0].quote } : {};
}

async function krakenMajors(): Promise<QuoteBook> {
  const data = await getJson<{
    result?: Record<string, { c?: string[]; o?: string }>;
  }>("https://api.kraken.com/0/public/Ticker?pair=XBTUSD,ETHUSD");

  const book: QuoteBook = {};
  const pack = (row?: { c?: string[]; o?: string }) => {
    const last = Number(row?.c?.[0]);
    const open = Number(row?.o);
    if (!Number.isFinite(last) || last <= 0) return null;
    const change =
      Number.isFinite(open) && open > 0 ? ((last - open) / open) * 100 : 0;
    return { usd: last, change };
  };

  const btc = pack(data.result?.XXBTZUSD);
  const eth = pack(data.result?.XETHZUSD);
  if (btc) book.bitcoin = btc;
  if (eth) book.ethereum = eth;
  return book;
}

export async function fetchQuotes(): Promise<QuoteBook> {
  const results = await Promise.allSettled([
    coinGecko(),
    kucoinBeldex(),
    dexScreenerBeldex(),
    krakenMajors(),
  ]);

  const book: QuoteBook = {};

  for (const result of results) {
    if (result.status !== "fulfilled") continue;
    Object.assign(book, result.value);
  }

  // Prefer CoinGecko when available, then KuCoin, then DEX Screener.
  const gecko = results[0];
  if (gecko.status === "fulfilled") {
    const preferred = gecko.value;
    if (preferred.bitcoin) book.bitcoin = preferred.bitcoin;
    if (preferred.ethereum) book.ethereum = preferred.ethereum;
    if (preferred.beldex) book.beldex = preferred.beldex;
  }

  if (!book.beldex) {
    throw new Error("No live Beldex price source is available");
  }

  return book;
}
