import { createFileRoute, Link } from "@tanstack/react-router";
import { useState, type FormEvent } from "react";
import { GuestShell } from "@/components/layout/app-shell";
import { toast } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { sendReset } from "@/lib/supabase/auth";

export const Route = createFileRoute("/forgot")({ component: ForgotPage });

function ForgotPage() {
  return (
    <GuestShell>
      <Forgot />
    </GuestShell>
  );
}

function Forgot() {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);

  const onEmail = async (e: FormEvent) => {
    e.preventDefault();
    const target = email.trim();
    if (!target || !target.includes("@")) {
      toast(t.useAccountEmail);
      return;
    }
    setBusy(true);
    const err = await sendReset(target);
    setBusy(false);
    if (err) {
      toast(err);
      return;
    }
    setSent(true);
    toast(t.checkEmailTitle);
  };

  return (
    <div className="flex min-h-[calc(100vh-64px)] items-center justify-center px-4 py-10">
      <div className="w-full max-w-[400px] rounded-xl border border-line bg-surface p-6 sm:p-8">
        <h2 className="text-[22px] font-bold">{t.forgotTitle}</h2>
        <p className="mt-1 text-[13px] text-subtle">{t.forgotLead}</p>
        {!sent ? (
          <form onSubmit={onEmail} className="mt-6 space-y-4">
            <div>
              <FieldLabel>{t.emailOrUser}</FieldLabel>
              <Input
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                autoComplete="username"
              />
            </div>
            <Button type="submit" className="w-full" disabled={busy}>
              {busy ? "…" : t.sendReset}
            </Button>
          </form>
        ) : (
          <div className="mt-6 rounded-md border border-line bg-elevated p-4 text-sm text-muted">
            {t.checkEmailBody}
          </div>
        )}
        <p className="mt-5 text-center text-xs text-subtle">
          <Link to="/login" className="text-accent">
            {t.signIn}
          </Link>
        </p>
      </div>
    </div>
  );
}
