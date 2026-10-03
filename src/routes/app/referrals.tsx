import { createFileRoute } from "@tanstack/react-router";
import { Copy } from "lucide-react";
import { toast } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { referralLink, usePlatform } from "@/lib/platform/store";
import { copy } from "@/lib/platform/i18n";
import { copyText, formatUsd } from "@/lib/utils";

export const Route = createFileRoute("/app/referrals")({ component: ReferralsPage });

function ReferralsPage() {
  const user = usePlatform((s) => s.user);
  const referralBonus = usePlatform((s) => s.referralBonus);
  const copyReferral = usePlatform((s) => s.copyReferral);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const link = referralLink(user);

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="text-xl font-bold">{t.referralTitle}</h2>
      <p className="mt-1 text-xs text-subtle">{t.referralLead}</p>
      <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
        <div className="text-[11px] text-muted">{t.referralEarned}</div>
        <div className="text-2xl font-bold tabular text-accent">{formatUsd(referralBonus)}</div>
        <div className="mt-5 text-[13px] font-semibold">{t.yourLink}</div>
        <div className="mt-2 break-all rounded-md border border-line-strong bg-surface px-3 py-3 text-[11px] text-muted">
          {link}
        </div>
        <Button
          className="mt-4 w-full"
          onClick={async () => {
            const next = copyReferral();
            await copyText(next);
            toast(t.linkCopied);
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
