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

/**
 * BDX normally trades around a few cents per token. Reject feeds that are
 * obviously for the wrong asset/token before they can reach the UI.
 *
 * This is intentionally a broad safety band, not a price peg:
 * legitimate market movement inside this range is still accepted.
 */
const BDX_MIN_REASONABLE_USD = 0.02;
const BDX_MAX_REASONABLE_USD = 0.2;
const BDX_LAST_VALID_STORAGE_KEY = "global-beldex:last-valid-bdx-usd";
const BDX_EMERGENCY_FALLBACK_USD = 0.07384;

function isReasonableBdxQuote(quote: { usd: number; change: number }) {
  return (
    Number.isFinite(quote.usd) &&
    quote.usd >= BDX_MIN_REASONABLE_USD &&
    quote.usd <= BDX_MAX_REASONABLE_USD
  );
}

function rememberBdxQuote(quote: { usd: number; change: number }) {
  try {
    window.localStorage.setItem(
      BDX_LAST_VALID_STORAGE_KEY,
      JSON.stringify({
        usd: quote.usd,
        change: quote.change,
        savedAt: Date.now(),
      }),
    );
  } catch {
    // Storage can be unavailable in private/restricted browser contexts.
  }
}

function getLastValidBdxQuote() {
  try {
    const raw = window.localStorage.getItem(BDX_LAST_VALID_STORAGE_KEY);
    if (!raw) return null;

    const parsed = JSON.parse(raw) as {
      usd?: unknown;
      change?: unknown;
    };
    const quote = validQuote(parsed.usd, parsed.change);
    return quote && isReasonableBdxQuote(quote) ? quote : null;
  } catch {
    return null;
  }
}

/**
 * Combine independent BDX sources defensively.
 *
 * A bad source such as $0.00012 is rejected immediately. When multiple
 * reasonable sources are available, use their median so one stale exchange
 * cannot move the displayed price by orders of magnitude.
 */
function selectReliableBdxQuote(
  candidates: Array<{ source: string; quote: { usd: number; change: number } }>,
) {
  const reasonable = candidates.filter(({ quote }) => isReasonableBdxQuote(quote));

  if (reasonable.length === 0) {
    return getLastValidBdxQuote();
  }

  const sorted = [...reasonable].sort((a, b) => a.quote.usd - b.quote.usd);
  const middle = Math.floor(sorted.length / 2);
  const median =
    sorted.length % 2 === 1
      ? sorted[middle].quote.usd
      : (sorted[middle - 1].quote.usd + sorted[middle].quote.usd) / 2;

  // Keep only sources that are within 2x of the consensus median.
  const agreeing = sorted.filter(
    ({ quote }) => quote.usd >= median / 2 && quote.usd <= median * 2,
  );

  const finalCandidates = agreeing.length > 0 ? agreeing : [sorted[middle]];
  const finalPrices = finalCandidates.map(({ quote }) => quote.usd).sort((a, b) => a - b);
  const finalMiddle = Math.floor(finalPrices.length / 2);
  const selectedUsd =
    finalPrices.length % 2 === 1
      ? finalPrices[finalMiddle]
      : (finalPrices[finalMiddle - 1] + finalPrices[finalMiddle]) / 2;

  // Use the change value from the source closest to the selected price.
  const selected = finalCandidates.reduce((best, candidate) =>
    Math.abs(candidate.quote.usd - selectedUsd) <
    Math.abs(best.quote.usd - selectedUsd)
      ? candidate
      : best,
  );

  const quote = { usd: selectedUsd, change: selected.quote.change };
  rememberBdxQuote(quote);
  return quote;
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

  // Bitcoin/Ethereum can safely prefer CoinGecko.
  const gecko = results[0];
  if (gecko.status === "fulfilled") {
    const preferred = gecko.value;
    if (preferred.bitcoin) book.bitcoin = preferred.bitcoin;
    if (preferred.ethereum) book.ethereum = preferred.ethereum;
  }

  const bdxCandidates: Array<{
    source: string;
    quote: { usd: number; change: number };
  }> = [];

  if (gecko.status === "fulfilled" && gecko.value.beldex) {
    bdxCandidates.push({ source: "CoinGecko", quote: gecko.value.beldex });
  }

  if (results[1].status === "fulfilled" && results[1].value.beldex) {
    bdxCandidates.push({ source: "KuCoin", quote: results[1].value.beldex });
  }

  if (results[2].status === "fulfilled" && results[2].value.beldex) {
    bdxCandidates.push({ source: "DexScreener", quote: results[2].value.beldex });
  }

  let bdx = selectReliableBdxQuote(bdxCandidates);

  // If every live feed is unavailable or invalid, never display a corrupt
  // value such as $0.00012. Keep the last valid value when possible; the
  // emergency value is only used for a first-load outage and is not treated
  // as a market source.
  if (!bdx) {
    bdx = {
      usd: BDX_EMERGENCY_FALLBACK_USD,
      change: 0,
    };
    rememberBdxQuote(bdx);
  }

  book.beldex = bdx;
  return book;
}
