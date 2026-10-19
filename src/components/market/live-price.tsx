import { useEffect, useRef, useState } from "react";
import { create } from "zustand";
import { TrendingDown, TrendingUp } from "lucide-react";
import { CoinLogo } from "@/components/market/coin-logo";
import { fetchQuotes } from "@/lib/market/live-quotes";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { cn } from "@/lib/utils";

type Quote = {
  usd: number | null;
  change24h: number | null;
  book: Record<string, { usd: number; change: number }>;
  updatedAt: number;
  status: "loading" | "ready" | "error";
};

const useQuote = create<Quote & { load: () => Promise<void> }>((set, get) => ({
  usd: null,
  change24h: null,
  book: {},
  updatedAt: 0,
  status: "loading",
  load: async () => {
    set({ status: "loading" });
    try {
      const book = await fetchQuotes();
      if (!book.bitcoin && !book.beldex && !book.ethereum) {
        set({ status: "error" });
        return;
      }
      set({
        usd: book.beldex?.usd ?? get().usd,
        change24h: book.beldex?.change ?? get().change24h,
        book: { ...get().book, ...book },
        updatedAt: Date.now(),
        status: "ready",
      });
    } catch {
      set({ status: get().usd ? "ready" : "error" });
    }
  },
}));

let liveStarted = false;
function ensureLive() {
  if (liveStarted || typeof window === "undefined") return;
  liveStarted = true;
  const tick = () => void useQuote.getState().load();
  void tick();
  window.setInterval(tick, 30000);
}

export function useBeldexQuote() {
  const q = useQuote();
  useEffect(() => {
    ensureLive();
  }, []);
  return q;
}

export function formatCoinUsd(usd: number) {
  if (usd >= 1000) {
    return `$${usd.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }
  if (usd >= 1) return `$${usd.toFixed(2)}`;
  return `$${usd.toFixed(5)}`;
}

export function coinQty(usdAmount: number, price: number) {
  if (!price || !usdAmount) return null;
  const n = usdAmount / price;
  if (n >= 1000) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  if (n >= 1) return n.toLocaleString(undefined, { maximumFractionDigits: 6 });
  return n.toFixed(6);
}

export function CoinPrice({ id }: { id: "beldex" | "bitcoin" | "ethereum" }) {
  const { book } = useBeldexQuote();
  const lang = usePlatform((s) => s.lang);
  const row = book[id];
  if (!row) {
    return <span className="text-[11px] tabular text-subtle">…</span>;
  }
  const up = row.change >= 0;
  return (
    <span className="text-right leading-tight">
      <span className="block text-[10px] text-subtle">{copy[lang].page.marketWord}</span>
      <span className="block text-[13px] font-bold tabular">
        <LiveFigure value={formatCoinUsd(row.usd)} />
      </span>
      <span className={up ? "text-[10px] tabular text-accent" : "text-[10px] tabular text-danger"}>
        {up ? "+" : ""}
        {row.change.toFixed(2)}%
      </span>
    </span>
  );
}

const BOARD = [
  { id: "beldex" as const, name: "Beldex", ticker: "BDX" },
];

export function MarketBoard({ active }: { active?: "bitcoin" | "ethereum" | "beldex" }) {
  const { book } = useBeldexQuote();
  const p = copy[usePlatform((s) => s.lang)].page;
  return (
    <div className="rounded-lg border border-line bg-elevated p-4">
      <div className="flex items-center justify-between">
        <div className="text-[11px] font-semibold tracking-wide text-subtle">{p.livePrice}</div>
        <div className="inline-flex items-center gap-1.5 text-[10px] text-accent">
          <span className="size-1.5 rounded-full bg-accent animate-pulse" />
          {p.liveWord}
        </div>
      </div>
      <div className="mt-3 grid gap-2">
        {BOARD.map((c) => {
          const row = book[c.id];
          const on = active === c.id;
          const up = (row?.change ?? 0) >= 0;
          return (
            <div
              key={c.id}
              className={
                on
                  ? "flex items-center justify-between rounded-md border border-accent/50 bg-accent/10 px-3 py-2.5"
                  : "flex items-center justify-between rounded-md border border-line bg-surface px-3 py-2.5"
              }
            >
              <div className="flex items-center gap-2.5">
                <CoinLogo coin={c.id} size={28} />
                <div>
                  <div className="text-[13px] font-semibold text-fg">{c.name}</div>
                  <div className="text-[10px] text-subtle">{c.ticker}</div>
                </div>
              </div>
              <div className="text-right">
                <div className="text-lg font-bold tabular">
                  {row ? <LiveFigure value={formatCoinUsd(row.usd)} /> : "…"}
                </div>
                {row && (
                  <div className={up ? "text-[10px] tabular text-accent" : "text-[10px] tabular text-danger"}>
                    {up ? "+" : ""}
                    {row.change.toFixed(2)}% 24h
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function BeldexLivePrice({ className }: { className?: string }) {
  const { usd, change24h } = useBeldexQuote();
  const p = copy[usePlatform((s) => s.lang)].page;
  const up = (change24h ?? 0) >= 0;
  return (
    <div className={cn("rounded-lg border border-line bg-elevated p-4", className)}>
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <CoinLogo coin="beldex" size={36} />
          <div>
            <div className="text-[11px] font-semibold tracking-wide text-subtle">{p.liveBeldex}</div>
            <div className="mt-0.5 text-[10px] text-subtle">BDX · BDXUSD</div>
          </div>
        </div>
        <div className="inline-flex items-center gap-1.5 text-[10px] text-accent">
          <span className="size-1.5 rounded-full bg-accent animate-pulse" />
          {p.liveWord}
        </div>
      </div>
      <div className="mt-2 flex items-end justify-between gap-3">
        <div className="text-3xl font-bold tabular">
          {usd == null ? "…" : <LiveFigure value={formatCoinUsd(usd)} />}
        </div>
        {change24h != null && (
          <div
            className={cn(
              "mb-1 inline-flex items-center gap-1 text-sm font-semibold tabular",
              up ? "text-accent" : "text-danger",
            )}
          >
            {up ? <TrendingUp size={14} /> : <TrendingDown size={14} />}
            {up ? "+" : ""}
            {change24h.toFixed(2)}%
          </div>
        )}
      </div>
    </div>
  );
}

function LiveFigure({ value }: { value: string }) {
  const prev = useRef(value);
  const [hot, setHot] = useState(false);
  useEffect(() => {
    if (prev.current === value) return;
    prev.current = value;
    setHot(true);
    const id = window.setTimeout(() => setHot(false), 500);
    return () => window.clearTimeout(id);
  }, [value]);
  return <span className={hot ? "text-accent" : "text-fg"}>{value}</span>;
}

export function LiveBadge({ className }: { className?: string }) {
  const p = copy[usePlatform((s) => s.lang)].page;
  return (
    <div
      className={cn(
        "inline-flex items-center gap-2 rounded-full border border-line-strong bg-elevated px-3 py-1 text-[11px] text-muted",
        className,
      )}
    >
      <span className="size-2 rounded-full bg-accent animate-pulse" />
      {p.liveBadge}
    </div>
  );
}

export function PriceChip() {
  const { usd, change24h } = useBeldexQuote();
  const up = (change24h ?? 0) >= 0;
  return (
    <div className="flex items-baseline gap-2">
      <span className="text-lg font-bold tabular">
        {usd == null ? "—" : <LiveFigure value={`$${usd.toFixed(5)}`} />}
      </span>
      {change24h != null && (
        <span
          className={cn(
            "inline-flex items-center gap-0.5 text-xs font-medium",
            up ? "text-accent" : "text-danger",
          )}
        >
          {up ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
          {up ? "+" : ""}
          {change24h.toFixed(2)}%
        </span>
      )}
    </div>
  );
}
