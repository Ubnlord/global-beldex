import { createFileRoute } from "@tanstack/react-router";
import { Copy } from "lucide-react";
import { toast, toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { referralLink, usePlatform } from "@/lib/platform/store";
import { copy } from "@/lib/platform/i18n";
import { copyText, formatBdx, formatUsd } from "@/lib/utils";

export const Route = createFileRoute("/app/referrals")({ component: ReferralsPage });

function ReferralsPage() {
  const user = usePlatform((s) => s.user);
  const referralBonus = usePlatform((s) => s.referralBonus);
  const txs = usePlatform((s) => s.txs);
  const bdxReferralBonus = txs
    .filter((tx) => tx.type === "referral" && tx.currency === "BDX" && tx.status === "completed")
    .reduce((sum, tx) => sum + tx.amount, 0);
  const copyReferral = usePlatform((s) => s.copyReferral);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const link = referralLink(user);

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="text-xl font-bold">{t.referralTitle}</h2>
      <p className="mt-1 text-xs text-subtle">{t.referralLead}</p>
      <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
        <div className="text-[11px] text-muted">{t.referralEarned} · USD</div>
        <div className="text-2xl font-bold tabular text-accent">{formatUsd(referralBonus)}</div>
        <div className="mt-4 text-[11px] text-muted">{t.referralEarned} · BDX</div>
        <div className="text-xl font-bold tabular text-emerald-300">{formatBdx(bdxReferralBonus)} BDX</div>
        <div className="mt-5 text-[13px] font-semibold">{t.yourLink}</div>
        <div className="mt-2 break-all rounded-md border border-line-strong bg-surface px-3 py-3 text-[11px] text-muted">
          {link}
        </div>
        <Button
          className="mt-4 w-full"
          onClick={async () => {
            const next = copyReferral();
            try {
              const copied = await copyText(next);
              if (!copied) {
                toastError("Couldn't copy the referral link. Please select and copy it manually.");
                return;
              }
              toast(t.linkCopied);
            } catch {
              toastError("Couldn't copy the referral link. Please select and copy it manually.");
            }
          }}
        >
          <Copy size={14} /> {t.copyLink}
        </Button>
        <p className="mt-3 text-[11px] text-subtle">
          {t.referralFine}
        </p>
      </div>
    </div>
  );
}
