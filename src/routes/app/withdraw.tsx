import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Shield, Zap } from "lucide-react";
import { useState } from "react";
import { toast, toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { CoinLogo } from "@/components/market/coin-logo";
import { WITHDRAW_METHODS } from "@/lib/platform/catalog";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { formatBdx } from "@/lib/utils";
import { validateWithdrawalDestination } from "@/lib/financial/withdrawal-address";
import { BdxBitcoinCalculator } from "@/components/financial/bdx-bitcoin-calculator";

const MIN_WITHDRAWAL = 76;

export const Route = createFileRoute("/app/withdraw")({ component: WithdrawPage });

function WithdrawPage() {
  const navigate = useNavigate();
  const bdxAvailable = usePlatform((s) => s.bdx);
  const withdraw = usePlatform((s) => s.withdraw);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [method, setMethod] = useState("Beldex");
  const [amount, setAmount] = useState("");
  const [address, setAddress] = useState("");
  const [requestId, setRequestId] = useState<string | null>(null);

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
    if (n < MIN_WITHDRAWAL) {
      toastError(`Minimum withdrawal is ${formatBdx(MIN_WITHDRAWAL)} BDX`);
      return;
    }
    const isBitcoin = method.toLowerCase().startsWith("bitcoin");
    const addressError = validateWithdrawalDestination(isBitcoin ? "Bitcoin" : "Beldex", address);
    if (addressError) {
      toastError(addressError);
      return;
    }
    const id = requestId ?? crypto.randomUUID();
    setRequestId(id);
    const err = await withdraw(n, isBitcoin ? "Bitcoin" : "Beldex", address, id, "BDX");
    if (err) {
      toastError(err);
      return;
    }
    toast(t.withdrawRequested);
    void navigate({ to: "/app/history" });
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="mt-4 text-xl font-bold">{t.withdrawTitle}</h2>
      <p className="mt-1 text-xs text-subtle">{t.withdrawLead}</p>

      <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
        <FieldLabel>{t.chooseMethod}</FieldLabel>
        <div className="mt-2 grid gap-2">
          {WITHDRAW_METHODS.map((m) => {
            const active = method === m.label;
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
                      BDX
                    </div>
                  </div>
                </div>
              </button>
            );
          })}
        </div>

        <FieldLabel>
          <span className="mt-4 block">Amount (BDX)</span>
        </FieldLabel>
        <div className="relative mt-2">
          <span className="absolute left-4 top-1/2 -translate-y-1/2 text-subtle">BDX</span>
          <Input
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            type="number"
            min={MIN_WITHDRAWAL}
            step="0.001"
            placeholder="Minimum 76 BDX"
            className="mt-0 h-14 border-2 border-line-strong bg-surface px-4 text-base font-medium placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/20"
          />
        </div>
        <div className="mt-2 flex justify-between text-[11px]">
          <span className="text-subtle">{t.available}: {formatBdx(bdxAvailable)} BDX · Min: {formatBdx(MIN_WITHDRAWAL)} BDX</span>
          <button type="button" onClick={() => setAmount(bdxAvailable.toFixed(3))} className="text-accent">
            {t.max}
          </button>
        </div>
        <FieldLabel>
          <span className="mt-5 block">{t.destination}</span>
        </FieldLabel>
        <Input
          value={address}
          onChange={(e) => setAddress(e.target.value)}
          placeholder="Paste your wallet address"
        />
{method.toLowerCase().startsWith("bitcoin") && <BdxBitcoinCalculator bdxAmount={amount} purpose="withdrawal" />}
                {method.toLowerCase().startsWith("bitcoin") && <div className="mt-3 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-subtle">Bitcoin withdrawals are requested against your BDX balance. An administrator must review the request, calculate the BTC payout, send it manually, and then mark it completed. Submitting this form does not send BTC.</div>}
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

