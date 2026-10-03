import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Shield, Zap } from "lucide-react";
import { useState } from "react";
import { AdvancedChart, TickerTape } from "@/components/market/tradingview";
import { BeldexLivePrice, CoinPrice, MarketBoard, coinQty, formatCoinUsd, useBeldexQuote } from "@/components/market/live-price";
import { toast, toastError } from "@/components/layout/toast";
import { TvCredit } from "@/components/platform/plan-card";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { CoinLogo } from "@/components/market/coin-logo";
import { WITHDRAW_METHODS } from "@/lib/platform/catalog";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { formatUsd } from "@/lib/utils";

export const Route = createFileRoute("/app/withdraw")({ component: WithdrawPage });

function WithdrawPage() {
  const navigate = useNavigate();
  const available = usePlatform((s) => s.available);
  const withdraw = usePlatform((s) => s.withdraw);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const { book } = useBeldexQuote();
  const [method, setMethod] = useState("");
  const [amount, setAmount] = useState("");
  const [address, setAddress] = useState("");

  const submit = () => {
    const n = parseFloat(amount);
    const err = withdraw(n, method, address);
    if (err) {
      toastError(err);
      return;
    }
    toast(t.withdrawRequested);
    void navigate({ to: "/app/history" });
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <TickerTape />
      <h2 className="mt-4 text-xl font-bold">{t.withdrawTitle}</h2>
      <p className="mt-1 text-xs text-subtle">{t.withdrawLead}</p>

      <div className="mt-4 rounded-lg border border-line bg-elevated p-4">
        <AdvancedChart />
        <TvCredit className="mt-2" />
      </div>

      <div className="mt-4">
        <BeldexLivePrice />
      </div>

      <div className="mt-4">
        <MarketBoard
          active={method === "Bitcoin" ? "bitcoin" : method === "Ethereum" ? "ethereum" : method === "Beldex" ? "beldex" : undefined}
        />
      </div>

      <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
        <FieldLabel>{t.chooseMethod}</FieldLabel>
        <div className="mt-2 grid gap-2">
          {WITHDRAW_METHODS.map((m) => {
            const active = method === m.label;
            const coin = m.id === "BTC" ? "bitcoin" : m.id === "ETH" ? "ethereum" : "beldex";
            return (
              <button
                key={m.id}
                type="button"
                onClick={() => setMethod(m.label)}
                className={
                  active
                    ? "flex items-center justify-between rounded-md border-2 border-accent bg-accent/10 p-3"
                    : "flex items-center justify-between rounded-md border border-line-strong p-3"
                }
              >
                <div className="flex items-center gap-2.5 text-left">
                  <CoinLogo coin={m.id} size={32} />
                  <div>
                    <div className="text-[13px] font-semibold text-fg">{m.label}</div>
                    <div className="text-[11px] text-subtle">
                      {m.id === "BTC" ? "BTC" : m.id === "ETH" ? "ETH" : "BDX"}
                    </div>
                  </div>
                </div>
                <CoinPrice id={coin} />
              </button>
            );
          })}
        </div>

        <FieldLabel>
          <span className="mt-5 block">{t.amount}</span>
        </FieldLabel>
        <div className="relative mt-2">
          <span className="absolute left-4 top-1/2 -translate-y-1/2 text-subtle">$</span>
          <Input
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            type="number"
            placeholder={t.enterAmount}
            className="mt-0 pl-8"
          />
        </div>
        <div className="mt-2 flex justify-between text-[11px]">
          <span className="text-subtle">{t.available}: {formatUsd(available)}</span>
          <button type="button" onClick={() => setAmount(String(available))} className="text-accent">
            {t.max}
          </button>
        </div>
        {method && (
          <CoinEstimate label={method} usd={parseFloat(amount) || 0} book={book} />
        )}

        <FieldLabel>
          <span className="mt-5 block">{t.destination}</span>
        </FieldLabel>
        <Input
          value={address}
          onChange={(e) => setAddress(e.target.value)}
          placeholder={
            method === "Bitcoin"
              ? "bc1..."
              : method === "Ethereum"
                ? "0x..."
                : method === "Beldex"
                  ? "bxd..."
                  : t.destPlaceholder
          }
        />
        <Button className="mt-6 w-full" onClick={submit}>
          {t.withdrawNow}
        </Button>
        <div className="mt-6 grid grid-cols-2 gap-3">
          <div className="flex gap-2 rounded-md border border-line bg-surface p-3">
            <Shield size={16} className="mt-0.5 text-accent" />
            <div>
              <div className="text-xs font-medium text-fg">{t.secure}</div>
              <div className="mt-1 text-[10px] text-subtle">{t.secureBody}</div>
            </div>
          </div>
          <div className="flex gap-2 rounded-md border border-line bg-surface p-3">
            <Zap size={16} className="mt-0.5 text-warn" />
            <div>
              <div className="text-xs font-medium text-fg">{t.fast}</div>
              <div className="mt-1 text-[10px] text-subtle">{t.fastBody}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function CoinEstimate({
  label,
  usd,
  book,
}: {
  label: string;
  usd: number;
  book: Record<string, { usd: number; change: number }>;
}) {
  const id = label === "Bitcoin" ? "bitcoin" : label === "Ethereum" ? "ethereum" : "beldex";
  const ticker = label === "Bitcoin" ? "BTC" : label === "Ethereum" ? "ETH" : "BDX";
  const row = book[id];
  if (!row) return null;
  const qty = usd > 0 ? coinQty(usd, row.usd) : null;
  return (
    <div className="mt-2 text-[11px] text-subtle">
      Market {formatCoinUsd(row.usd)}
      {qty ? ` · ≈ ${qty} ${ticker}` : ""}
    </div>
  );
}
