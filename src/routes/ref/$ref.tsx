import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect } from "react";
import { GuestShell } from "@/components/layout/app-shell";

export const Route = createFileRoute("/ref/$ref")({ component: ReferralRedirectPage });

function ReferralRedirectPage() {
  return (
    <GuestShell>
      <ReferralRedirect />
    </GuestShell>
  );
}

function ReferralRedirect() {
  const navigate = useNavigate();
  const { ref } = Route.useParams();

  useEffect(() => {
    const referral = ref.trim();
    if (!referral) {
      void navigate({ to: "/" });
      return;
    }
    void navigate({
      to: "/register",
      search: { ref: referral },
      replace: true,
    });
  }, [navigate, ref]);

  return (
    <div className="flex min-h-[calc(100vh-64px)] items-center justify-center px-4 py-10">
      <div className="rounded-xl border border-line bg-surface px-6 py-5 text-center">
        <div className="text-sm font-semibold text-fg">Opening referral registration…</div>
        <div className="mt-1 text-xs text-subtle">Referral code: {ref}</div>
      </div>
    </div>
  );
}
