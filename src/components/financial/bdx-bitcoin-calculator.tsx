import { useEffect, useState } from "react";

type Quote = { bdxUsd: number; btcUsd: number };
function price(value: unknown): number | null { const n = Number(value); return Number.isFinite(n) && n > 0 ? n : null; }
async function fetchQuote(): Promise<Quote> {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 6500);
  try {
    const response = await fetch("https://api.coingecko.com/api/v3/simple/price?ids=beldex,bitcoin&vs_currencies=usd", { headers: { accept: "application/json" }, cache: "no-store", signal: controller.signal });
    if (!response.ok) throw new Error("Quote unavailable");
    const data = await response.json() as Record<string, { usd?: unknown }>;
    const bdxUsd = price(data.beldex?.usd); const btcUsd = price(data.bitcoin?.usd);
    if (!bdxUsd || !btcUsd) throw new Error("Quote unavailable");
    return { bdxUsd, btcUsd };
  } finally { window.clearTimeout(timeout); }
}
export function BdxBitcoinCalculator({ bdxAmount, purpose }: { bdxAmount: string; purpose: "deposit" | "withdrawal" }) {
  const [quote, setQuote] = useState<Quote | null>(null);
  useEffect(() => {
    let active = true;
    const refresh = async () => { try { const q = await fetchQuote(); if (active) setQuote(q); } catch { if (active) setQuote(null); } };
    void refresh(); const timer = window.setInterval(() => void refresh(), 60000);
    return () => { active = false; window.clearInterval(timer); };
  }, []);
  const amount = Number(bdxAmount);
  const btc = quote && Number.isFinite(amount) && amount > 0 ? amount * quote.bdxUsd / quote.btcUsd : null;
  const formatBtc = (n: number) => n.toLocaleString("en-US", { maximumFractionDigits: 8 });
  return <section className="mt-4 rounded-md border border-line bg-surface p-3" aria-live="polite">
    <div className="flex items-center justify-between gap-2"><div className="text-xs font-semibold text-fg">BDX ⇄ Bitcoin calculator</div><div className="text-[10px] text-subtle">{quote ? "Live market estimate" : "Rate unavailable"}</div></div>
    <div className="mt-2 flex items-baseline justify-between gap-3"><span className="text-xs text-subtle">{purpose === "deposit" ? "Estimated BTC to send" : "Estimated BTC payout"}</span><strong className="text-sm tabular text-accent">{btc === null ? "— BTC" : formatBtc(btc) + " BTC"}</strong></div>
    {quote ? <p className="mt-1 text-[10px] text-subtle">Reference rates: 1 BDX ≈ ${quote.bdxUsd.toFixed(8)} USD · 1 BTC ≈ ${quote.btcUsd.toLocaleString("en-US", { maximumFractionDigits: 2 })} USD</p> : <p className="mt-1 text-[10px] text-subtle">Live rates unavailable. Try again when connected; no rate is guessed.</p>}
    <p className="mt-2 text-[10px] text-subtle">Estimate only—not a locked quote. Fees, spread, and market movement may change the final amount. {purpose === "deposit" ? "BDX credit remains subject to administrator verification and approval." : "Bitcoin withdrawals are manually reviewed and paid; this calculator does not send BTC or guarantee payout."}</p>
  </section>;
}
