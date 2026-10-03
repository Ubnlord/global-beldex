import { useEffect, useState } from "react";
import { fetchBeldexDetail, type BeldexDetail } from "@/lib/market/quotes";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { CoinLogo } from "@/components/market/coin-logo";
import { cn } from "@/lib/utils";

const RANGES = ["24h", "7d", "1m", "3m", "6m", "YTD", "1y"] as const;

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
  return `${n >= 0 ? "" : ""}${n.toFixed(1)}%`;
}

export function HomeBeldexStats() {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [detail, setDetail] = useState<BeldexDetail | null>(null);
  const [range, setRange] = useState<(typeof RANGES)[number]>("24h");

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

  const change = detail?.changes[range] ?? null;
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
            <div className="text-lg font-bold tabular">{money(detail?.usd ?? null)}</div>
            <div className={cn("text-xs font-semibold tabular", up ? "text-accent" : "text-danger")}>
              {pct(detail?.changes["24h"] ?? null)}
            </div>
          </div>
        </div>
        <div className="mt-4 grid grid-cols-2 gap-3 text-[12px]">
          <Stat label="Market Cap Rank" value={detail?.rank ? `#${detail.rank}` : "—"} />
          <Stat label="Market Cap" value={detail?.marketCap ? `$${compact(detail.marketCap)}` : "—"} />
          <Stat label="24h Volume" value={detail?.volume ? `$${compact(detail.volume)}` : "—"} />
          <Stat
            label="24h High/Low"
            value={`${money(detail?.high ?? null)} / ${money(detail?.low ?? null)}`}
          />
        </div>
        <div className="mt-3 text-[10px] text-subtle">{t.page.poweredBy}</div>
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
            <div className="font-semibold tabular">{money(detail?.usd ?? null)}</div>
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
