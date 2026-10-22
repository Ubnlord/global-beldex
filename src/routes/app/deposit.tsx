import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Check, Copy } from "lucide-react";
import { useEffect, useState } from "react";
import { toast, toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { DEPOSIT_METHODS } from "@/lib/platform/catalog";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { formatBdx, copyText } from "@/lib/utils";

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
    const err = await deposit(n, DEPOSIT_METHODS[method].title, requestId ?? crypto.randomUUID(), "BDX");
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
          <FieldLabel><span className="mt-4 block">Amount (BDX)</span></FieldLabel>
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
            via {DEPOSIT_METHODS[method].title}
            {" · BDX amount only"}
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

