import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Check, Copy } from "lucide-react";
import { useEffect, useState } from "react";
import { TickerTape } from "@/components/market/tradingview";
import { BeldexLivePrice, CoinPrice, MarketBoard, coinQty, formatCoinUsd, useBeldexQuote } from "@/components/market/live-price";
import { toast, toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { CoinLogo } from "@/components/market/coin-logo";
import { DEPOSIT_METHODS } from "@/lib/platform/catalog";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { BDX_USD_RATE, bdxToUsd, formatBdx, formatUsd, copyText } from "@/lib/utils";

export const Route = createFileRoute("/app/deposit")({ component: DepositPage });

async function copyAddress(value: string, message: string) {
  await copyText(value);
  toast(message);
}

function DepositPage() {
  const navigate = useNavigate();
  const deposit = usePlatform((s) => s.deposit);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const { book } = useBeldexQuote();
  const [amount, setAmount] = useState("");
  const isBeldex = method === "BELDEX";
  const [method, setMethod] = useState<keyof typeof DEPOSIT_METHODS>("BELDEX");
  const [step, setStep] = useState<"form" | "pay">(() => {
    if (typeof window === "undefined") return "form";
    return new URLSearchParams(window.location.search).get("step") === "pay" ? "pay" : "form";
  });
  const [requestId, setRequestId] = useState<string | null>(null);

  useEffect(() => {
    const handlePopState = () => {
      const isPayStep = new URLSearchParams(window.location.search).get("step") === "pay";
      setStep(isPayStep ? "pay" : "form");
    };

    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  const quoteId = method === "BTC" ? "bitcoin" : method === "ETH" ? "ethereum" : "beldex";
  const ticker = method === "BTC" ? "BTC" : method === "ETH" ? "ETH" : "BDX";
  const spot = book[quoteId];
  const qty = isBeldex ? null : coinQty(parseFloat(amount) || 0, spot?.usd ?? 0);

  const goPay = () => {
    const n = parseFloat(amount);
    if (!n || (isBeldex ? n < 4000 : n < 300)) {
      toast(t.err.MIN_DEPOSIT);
      return;
    }
    setRequestId(crypto.randomUUID());
    const url = new URL(window.location.href);
    url.searchParams.set("step", "pay");
    window.history.pushState({ depositStep: "pay" }, "", url);
    setStep("pay");
  };

  const confirm = async () => {
    const n = parseFloat(amount);
    const err = await deposit(n, DEPOSIT_METHODS[method].title, requestId ?? crypto.randomUUID());
    if (err) {
      toastError(err);
      return;
    }
    toast(t.depositStarted);
    void navigate({ to: "/app/history" });
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <div className="mb-4">
        <TickerTape />
      </div>
      <h2 className="text-xl font-bold">{t.depositTitle}</h2>
      <p className="mt-1 text-xs text-subtle">{t.depositLead}</p>

      <div className="mt-4">
        <BeldexLivePrice />
      </div>

      <div className="mt-4">
        <MarketBoard active={quoteId} />
      </div>

      {step === "form" ? (
        <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
          <FieldLabel>{isBeldex ? "Amount (BDX)" : t.amountUsd}</FieldLabel>
          <div className="relative mt-2">
            <span className="absolute left-4 top-1/2 -translate-y-1/2 text-subtle">{isBeldex ? "BDX" : "$"}</span>
            <Input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              type="number"
              placeholder={isBeldex ? "Enter BDX amount..." : "Enter amount... Min $300"}
              className="mt-0 pl-8"
            />
          </div>
          <div className="mt-2 text-[10px] text-subtle">
            {isBeldex ? `Minimum: ${formatBdx(4000)} · ${formatUsd(bdxToUsd(4000), 3)} · 1 BDX = ${formatUsd(BDX_USD_RATE, 6)}` : t.minHint}
          </div>
          <div className="mt-5">
            <div className="mb-2 text-[11px] text-muted">{t.payMethod}</div>
            <div className="grid gap-2">
              <button
                type="button"
                onClick={() => setMethod("BELDEX")}
                className={
                  method === "BELDEX"
                    ? "flex items-center justify-between rounded-md border-2 border-accent bg-accent/10 p-3"
                    : "flex items-center justify-between rounded-md border border-line-strong p-3 opacity-60"
                }
              >
                <div className="flex items-center gap-3">
                  <CoinLogo coin="beldex" size={32} />
                  <div>
                    <div className="text-[13px] font-semibold text-fg">{t.beldexInstant}</div>
                    <div className="text-[11px] text-subtle">{t.beldexDetail}</div>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <CoinPrice id="beldex" />
                  {method === "BELDEX" && (
                    <div className="flex size-5 items-center justify-center rounded-full bg-accent text-accent-fg">
                      <Check size={12} />
                    </div>
                  )}
                </div>
              </button>
              <Method
                active={method === "BTC"}
                onClick={() => setMethod("BTC")}
                coin="bitcoin"
                title="Bitcoin"
                detail="BTC · 1-2 hrs"
              />
              <Method
                active={method === "ETH"}
                onClick={() => setMethod("ETH")}
                coin="ethereum"
                title="Ethereum"
                detail="ETH · ERC-20"
              />
            </div>
          </div>
          <Button className="mt-6 w-full" onClick={goPay}>
            {t.continuePay}
          </Button>
        </div>
      ) : (
        <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
          <div className="text-xs text-muted">{t.sendExactly}</div>
          <div className="text-2xl font-bold tabular text-accent">
            {isBeldex ? `${formatBdx(parseFloat(amount || "0"))} · ${formatUsd(bdxToUsd(parseFloat(amount || "0")), 3)}` : `${parseFloat(amount || "0").toFixed(2)}`}
          </div>
          <div className="mt-1 text-[11px] text-subtle">
            via {DEPOSIT_METHODS[method].title}
            {isBeldex ? ` · Platform rate: 1 BDX = ${formatUsd(BDX_USD_RATE, 6)}` : spot ? ` · ${formatCoinUsd(spot.usd)}` : ""}
          </div>
          {isBeldex ? (
            <div className="mt-3 rounded-md border border-accent/30 bg-accent/5 px-3 py-2.5">
              <div className="text-[10px] text-subtle">Account conversion rate</div>
              <div className="mt-1 flex items-end justify-between gap-3">
                <div className="text-lg font-bold tabular text-fg">{formatUsd(BDX_USD_RATE, 6)} / BDX</div>
                <div className="text-right text-sm font-semibold tabular text-accent">
                  {formatUsd(bdxToUsd(parseFloat(amount || "0")), 3)} USD
                </div>
              </div>
              <div className="mt-1 text-[10px] text-subtle">This platform uses the fixed BDX denomination rate for deposits.</div>
            </div>
          ) : qty && spot ? (
            <div className="mt-3 rounded-md border border-line bg-surface px-3 py-2.5">
              <div className="text-[10px] text-subtle">Live market price</div>
              <div className="mt-1 flex items-end justify-between">
                <div className="text-lg font-bold tabular text-fg">{formatCoinUsd(spot.usd)}</div>
                <div className="text-sm font-semibold tabular text-accent">
                  ≈ {qty} {ticker}
                </div>
              </div>
            </div>
          ) : null}
          <div className="mt-5">
            <FieldLabel>{t.depositAddress}</FieldLabel>
            <div className="mt-2 flex gap-2">
              <button
                type="button"
                onClick={() => copyAddress(DEPOSIT_METHODS[method].address, t.addressCopied)}
                className="min-w-0 flex-1 break-all rounded-md border border-line-strong bg-surface px-3 py-3 text-left text-[11px] text-muted"
              >
                {DEPOSIT_METHODS[method].address}
              </button>
              <Button
                variant="secondary"
                size="icon"
                onClick={() => copyAddress(DEPOSIT_METHODS[method].address, t.addressCopied)}
                aria-label={t.addressCopied}
              >
                <Copy size={14} />
              </Button>
            </div>
          </div>
          <img
            src={DEPOSIT_METHODS[method].qr}
            alt={`${DEPOSIT_METHODS[method].title} deposit QR`}
            className="mx-auto mt-5 size-56 rounded-xl bg-white p-2"
          />
          <p className="mt-3 text-[11px] text-subtle">
            {t.simAddress}
          </p>
          <div className="mt-6 flex gap-2">
            <Button
              variant="secondary"
              className="flex-1"
              onClick={() => {
                if (window.history.state?.depositStep === "pay") {
                  window.history.back();
                } else {
                  setStep("form");
                }
              }}
            >
              {t.back}
            </Button>
            <Button className="flex-1" onClick={confirm}>
              {t.sentIt}
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

function Method({
  active,
  onClick,
  title,
  detail,
  coin,
}: {
  active: boolean;
  onClick: () => void;
  title: string;
  detail: string;
  coin: "bitcoin" | "ethereum" | "beldex";
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        active
          ? "flex items-center justify-between rounded-md border-2 border-accent bg-accent/10 p-3"
          : "flex items-center justify-between rounded-md border border-line-strong p-3"
      }
    >
      <div className="flex items-center gap-3">
        <CoinLogo coin={coin} size={32} />
        <div className="text-left">
          <div className="text-[13px] text-fg">{title}</div>
          <div className="text-[11px] text-subtle">{detail}</div>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <CoinPrice id={coin} />
        {active && (
          <div className="flex size-5 items-center justify-center rounded-full bg-accent text-accent-fg">
            <Check size={12} />
          </div>
        )}
      </div>
    </button>
  );
}
