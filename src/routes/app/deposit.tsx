import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Bitcoin, Copy } from "lucide-react";
import { useEffect, useState } from "react";
import { toast, toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { DEPOSIT_METHODS } from "@/lib/platform/catalog";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { formatBdx, copyText } from "@/lib/utils";
import { BdxBitcoinCalculator } from "@/components/financial/bdx-bitcoin-calculator";

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
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState<"BELDEX" | "BITCOIN">("BELDEX");
  const [bitcoinTxid, setBitcoinTxid] = useState("");
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


  const goPay = () => {
    const n = parseFloat(amount);
    if (!Number.isFinite(n) || n < 4000) {
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
    if (method === "BITCOIN" && !/^[0-9a-fA-F]{64}$/.test(bitcoinTxid.trim())) {
      toastError("Enter the 64-character Bitcoin transaction ID");
      return;
    }
    const err = await deposit(n, method === "BITCOIN" ? "Bitcoin" : DEPOSIT_METHODS.BELDEX.title, requestId ?? crypto.randomUUID(), "BDX", method === "BITCOIN" ? bitcoinTxid.trim() : undefined);
    if (err) {
      toastError(err);
      return;
    }
    toast(t.depositStarted);
    void navigate({ to: "/app/history" });
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="text-xl font-bold">{t.depositTitle}</h2>
      <p className="mt-1 text-xs text-subtle">{t.depositLead}</p>

      {step === "form" ? (
        <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
          <FieldLabel>Deposit method</FieldLabel>
          <div className="mt-2 grid grid-cols-2 gap-2">
            <Button type="button" variant={method === "BELDEX" ? "primary" : "secondary"} onClick={() => setMethod("BELDEX")} className="flex items-center justify-center gap-2">
              <img src="/coins/beldex.png" alt="" aria-hidden="true" className="size-6 shrink-0 rounded-full object-contain" />
              <span>Beldex (BDX)</span>
            </Button>
            <Button type="button" variant={method === "BITCOIN" ? "primary" : "secondary"} onClick={() => setMethod("BITCOIN")} className="flex items-center justify-center gap-2">
              <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-orange-500 text-white"><Bitcoin size={17} strokeWidth={2.5} /></span>
              <span>Bitcoin (BTC)</span>
            </Button>
          </div>
          <FieldLabel><span className="mt-4 block">Amount to credit (BDX)</span></FieldLabel>
          <div className="relative mt-2">
            <Input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              type="number"
              placeholder={"Enter BDX amount... Min 4,000"}
              className="mt-0 h-14 border-2 border-line-strong bg-surface px-4 text-base font-medium placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/20"
            />
          </div>
          <div className="mt-2 text-[10px] text-subtle">
            {`Minimum: ${formatBdx(4000)} BDX`}
          </div>
          {method === "BITCOIN" && <BdxBitcoinCalculator bdxAmount={amount} purpose="deposit" />}
          <Button className="mt-6 w-full" onClick={goPay}>
            {t.continuePay}
          </Button>
        </div>
      ) : (
        <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
          <div className="text-xs text-muted">{t.sendExactly}</div>
          <div className="text-2xl font-bold tabular text-accent">
            {`${formatBdx(parseFloat(amount || "0"))} BDX`}
          </div>
          <div className="mt-1 text-[11px] text-subtle">
            via {method === "BITCOIN" ? "Bitcoin (BTC)" : DEPOSIT_METHODS.BELDEX.title}
            {" · BDX wallet credit after admin approval"}
          </div>
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
          {method === "BELDEX" ? <img src={DEPOSIT_METHODS.BELDEX.qr} alt="Beldex deposit QR" className="mx-auto mt-5 size-56 rounded-xl bg-white p-2" /> : <div className="mt-4 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-subtle">Send Bitcoin on the Bitcoin network only. Your deposit is not credited automatically. An administrator must verify the payment and approve the BDX credit.</div>}
          {method === "BITCOIN" && <div className="mt-4"><FieldLabel>Bitcoin transaction ID (TXID)</FieldLabel><Input value={bitcoinTxid} onChange={(e) => setBitcoinTxid(e.target.value)} placeholder="Paste the 64-character transaction ID" className="mt-2" /></div>}
          <p className="mt-3 text-[11px] text-subtle">
            {method === "BITCOIN" ? "BTC deposits are reviewed by an administrator before BDX is credited. Keep your transaction ID." : t.simAddress}
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

