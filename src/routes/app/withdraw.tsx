import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Shield, Zap } from "lucide-react";
import { useState } from "react";
import { TickerTape } from "@/components/market/tradingview";
import { BeldexLivePrice, CoinPrice, MarketBoard, coinQty, formatCoinUsd, useBeldexQuote } from "@/components/market/live-price";
import { toast, toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { CoinLogo } from "@/components/market/coin-logo";
import { WITHDRAW_METHODS } from "@/lib/platform/catalog";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { formatBdx, formatUsd } from "@/lib/utils";
import { validateWithdrawalDestination } from "@/lib/financial/withdrawal-address";

const MIN_WITHDRAWAL = 300;

export const Route = createFileRoute("/app/withdraw")({ component: WithdrawPage });

function WithdrawPage() {
  const navigate = useNavigate();
  const available = usePlatform((s) => s.available);
  const bdxAvailable = usePlatform((s) => s.bdx);
  const withdraw = usePlatform((s) => s.withdraw);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const { book } = useBeldexQuote();
  const [method, setMethod] = useState("Beldex");
  const [amount, setAmount] = useState("");
  const [address, setAddress] = useState("");
  const [requestId, setRequestId] = useState<string | null>(null);
  const isBeldex = method === "Beldex";

  const submit = async () => {
    const n = parseFloat(amount);
    if (!method) {
      toastError("Please select a withdrawal method");
      return;
    }
    if (!Number.isFinite(n) || n <= 0) {
      toastError("Amount must be greater than zero");
      return;
    }
    const minimum = isBeldex ? 4000 : MIN_WITHDRAWAL;
    if (n < minimum) {
      toastError(isBeldex
        ? `Minimum withdrawal is ${formatBdx(4000)} BDX`
        : `Minimum withdrawal is ${MIN_WITHDRAWAL} USD`);
      return;
    }
    const addressError = validateWithdrawalDestination(method, address);
    if (addressError) {
      toastError(addressError);
      return;
    }
    const id = requestId ?? crypto.randomUUID();
    setRequestId(id);
    const err = await withdraw(n, method, address, id, isBeldex ? "BDX" : "USD");
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
            const coin = "beldex";
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
                      {"BDX"}
                    </div>
                  </div>
                </div>
                <CoinPrice id={coin} />
              </button>
            );
          })}
        </div>

        <FieldLabel>
          <span className="mt-4 block">{isBeldex ? "Amount (BDX)" : "Amount (USD)"}</span>
        </FieldLabel>
        <div className="relative mt-2">
          <span className="absolute left-4 top-1/2 -translate-y-1/2 text-subtle">{isBeldex ? "BDX" : "$"}</span>
          <Input
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            type="number"
            min={isBeldex ? 4000 : MIN_WITHDRAWAL}
            step="0.001"
            placeholder={isBeldex ? "Minimum 4,000 BDX" : "Minimum $300"}
            className="mt-0 h-14 border-2 border-line-strong bg-surface px-4 text-base font-medium placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/20"
          />
        </div>
        <div className="mt-2 flex justify-between text-[11px]">
          <span className="text-subtle">{t.available}: {isBeldex ? `${formatBdx(bdxAvailable)} BDX` : formatUsd(available)} · Min: {isBeldex ? `${formatBdx(4000)} BDX` : formatUsd(MIN_WITHDRAWAL)}</span>
          <button type="button" onClick={() => setAmount((isBeldex ? bdxAvailable : available).toFixed(3))} className="text-accent">
            {t.max}
          </button>
        </div>
        {method && (
          <CoinEstimate label={method} amount={parseFloat(amount) || 0} usd={parseFloat(amount) || 0} book={book} />
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
  amount,
  book,
}: {
  label: string;
  usd: number;
  amount: number;
  book: Record<string, { usd: number; change: number }>;
}) {
  const id = label === "Bitcoin" ? "bitcoin" : label === "Ethereum" ? "ethereum" : "beldex";
  const ticker = label === "Bitcoin" ? "BTC" : label === "Ethereum" ? "ETH" : "BDX";
  if (id === "beldex") {
    return null;
  }
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
