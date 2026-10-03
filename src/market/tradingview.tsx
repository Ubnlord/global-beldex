import { useEffect, useRef, useState } from "react";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { cn } from "@/lib/utils";

type WidgetKind = "tape" | "chart" | "overview" | "chart-sm";

const CONFIG: Record<
  WidgetKind,
  { src: string; payload: Record<string, unknown>; height: number | "auto" }
> = {
  tape: {
    src: "https://s3.tradingview.com/external-embedding/embed-widget-ticker-tape.js",
    height: 46,
    payload: {
      symbols: [
        { proName: "CRYPTO:BDXUSD", title: "Beldex" },
        { proName: "BINANCE:BTCUSDT", title: "Bitcoin" },
        { proName: "BINANCE:ETHUSDT", title: "Ethereum" },
        { proName: "BINANCE:SOLUSDT", title: "Solana" },
        { proName: "BINANCE:XRPUSDT", title: "Ripple" },
      ],
      showSymbolLogo: true,
      colorTheme: "dark",
      isTransparent: true,
      displayMode: "adaptive",
      locale: "en",
    },
  },
  "chart-sm": {
    src: "https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js",
    height: 280,
    payload: {
      autosize: true,
      symbol: "CRYPTO:BDXUSD",
      interval: "60",
      timezone: "Etc/UTC",
      theme: "dark",
      style: "1",
      locale: "en",
      allow_symbol_change: true,
      calendar: false,
      support_host: "https://www.tradingview.com",
    },
  },
  chart: {
    src: "https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js",
    height: 400,
    payload: {
      autosize: true,
      symbol: "CRYPTO:BDXUSD",
      interval: "D",
      timezone: "Etc/UTC",
      theme: "dark",
      style: "1",
      locale: "en",
      allow_symbol_change: true,
      calendar: false,
      support_host: "https://www.tradingview.com",
    },
  },
  overview: {
    src: "https://s3.tradingview.com/external-embedding/embed-widget-symbol-overview.js",
    height: 360,
    payload: {
      symbols: [["Beldex", "CRYPTO:BDXUSD|1D"]],
      chartOnly: false,
      width: "100%",
      height: "100%",
      locale: "en",
      colorTheme: "dark",
      autosize: true,
      showVolume: true,
      showMA: true,
      hideDateRanges: false,
      hideMarketStatus: false,
      hideSymbolLogo: false,
      scalePosition: "right",
      scaleMode: "Normal",
      fontFamily: "Inter, -apple-system, BlinkMacSystemFont, sans-serif",
      fontSize: "10",
      noTimeScale: false,
      valuesTracking: "1",
      changeMode: "price-and-percent",
      chartType: "area",
      maLineColor: "#2AF5D4",
      maLineWidth: 1,
      maLength: 9,
      lineWidth: 2,
      lineType: 0,
      dateRanges: ["1d|1", "1m|30", "3m|60", "12m|1D", "60m|1W", "all|1M"],
    },
  },
};

function Fallback({ kind }: { kind: WidgetKind }) {
  const p = copy[usePlatform((s) => s.lang)].page;
  if (kind === "tape") {
    return (
      <div className="flex h-full min-h-[46px] items-center gap-6 overflow-hidden px-4 text-xs text-muted">
        {["BDXUSD", "BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT"].map((s) => (
          <span key={s} className="shrink-0">
            <span className="text-fg font-medium">{s}</span>
            <span className="ml-2 text-accent">{p.liveWord}</span>
          </span>
        ))}
      </div>
    );
  }
  return (
    <div className="flex h-full min-h-[200px] flex-col items-center justify-center gap-2 px-4 text-center">
      <div className="text-sm font-semibold text-fg">{p.liveBdx}</div>
      <p className="text-xs text-subtle max-w-xs">{p.chartFallback}</p>
      <a
        href="https://www.tradingview.com/symbols/BDXUSD/"
        target="_blank"
        rel="noopener noreferrer"
        className="text-xs text-accent hover:underline"
      >
        {p.trackOnTv}
      </a>
    </div>
  );
}

export function TradingViewWidget({
  kind,
  className,
}: {
  kind: WidgetKind;
  className?: string;
}) {
  const host = useRef<HTMLDivElement>(null);
  const [failed, setFailed] = useState(false);
  const [ready, setReady] = useState(false);
  const cfg = CONFIG[kind];

  useEffect(() => {
    const el = host.current;
    if (!el) return;
    el.innerHTML = "";
    const wrap = document.createElement("div");
    wrap.className = "tradingview-widget-container";
    wrap.style.width = "100%";
    wrap.style.height = cfg.height === "auto" ? "100%" : `${cfg.height}px`;
    const widget = document.createElement("div");
    widget.className = "tradingview-widget-container__widget";
    widget.style.width = "100%";
    widget.style.height =
      kind === "tape" ? "100%" : "calc(100% - 32px)";
    wrap.appendChild(widget);
    const script = document.createElement("script");
    script.type = "text/javascript";
    script.src = cfg.src;
    script.async = true;
    script.innerHTML = JSON.stringify(cfg.payload);
    script.onerror = () => setFailed(true);
    wrap.appendChild(script);
    el.appendChild(wrap);
    const watch = window.setInterval(() => {
      if (el.querySelector("iframe")) {
        setReady(true);
        window.clearInterval(watch);
      }
    }, 300);
    const t = window.setTimeout(() => {
      if (!el.querySelector("iframe")) setFailed(true);
      window.clearInterval(watch);
    }, 8000);
    return () => {
      window.clearTimeout(t);
      window.clearInterval(watch);
      setReady(false);
      el.innerHTML = "";
    };
  }, [kind, cfg]);

  const h = cfg.height === "auto" ? undefined : cfg.height;

  return (
    <div
      className={cn(
        "relative w-full overflow-hidden rounded-md border border-line bg-panel",
        className,
      )}
      style={h ? { minHeight: h, height: h } : { minHeight: 46 }}
    >
      {(!ready || failed) && (
        <div className="absolute inset-0">
          <Fallback kind={kind} />
        </div>
      )}
      <div
        ref={host}
        className={cn("h-full w-full", !ready || failed ? "invisible" : "relative")}
      />
    </div>
  );
}

export function TickerTape() {
  return <TradingViewWidget kind="tape" className="min-h-[46px]" />;
}

export function MiniChart() {
  return <TradingViewWidget kind="chart-sm" />;
}

export function AdvancedChart() {
  return <TradingViewWidget kind="chart" />;
}

export function SymbolOverview() {
  return <TradingViewWidget kind="overview" />;
}
