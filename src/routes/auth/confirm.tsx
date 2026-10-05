import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, type FormEvent } from "react";
import { GuestShell } from "@/components/layout/app-shell";
import { toast } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { completeAuthRedirect, updateCloudPassword, type CloudProfile } from "@/lib/supabase/auth";

export const Route = createFileRoute("/auth/confirm")({ component: ConfirmPage });

function ConfirmPage() {
  return (
    <GuestShell>
      <Confirm />
    </GuestShell>
  );
}

function Confirm() {
  const navigate = useNavigate();
  const setUserProfile = usePlatform((s) => s.setUserProfile);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [error, setError] = useState("");
  const [recovery, setRecovery] = useState(false);
  const [profile, setProfile] = useState<CloudProfile | null>(null);
  const [next, setNext] = useState("");
  const [repeat, setRepeat] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let gone = false;
    void (async () => {
      const params = new URLSearchParams(window.location.search);
      const result = await completeAuthRedirect(params.get("code"));
      if (gone) return;
      if (result.error || !result.profile) {
        setError(result.error || t.page.linkExpired);
        return;
      }
      setProfile(result.profile);
      if (params.get("type") === "recovery") {
        setRecovery(true);
        return;
      }
      setUserProfile(result.profile);
      toast(t.created);
      void navigate({ to: "/app" });
    })();
    return () => {
      gone = true;
    };
  }, [enterAccount, navigate, t.created]);

  const onSave = async (e: FormEvent) => {
    e.preventDefault();
    if (next !== repeat) {
      toast(t.mismatch);
      return;
    }
    setBusy(true);
    const err = await updateCloudPassword(next);
    setBusy(false);
    if (err) {
      toast(err === "no-session" ? t.page.linkExpired : err);
      return;
    }
    if (profile) setUserProfile(profile);
    toast(t.passwordUpdated);
    void navigate({ to: "/app" });
  };

  return (
    <div className="flex min-h-[calc(100vh-64px)] items-center justify-center px-4 py-10">
      <div className="w-full max-w-[400px] rounded-xl border border-line bg-surface p-6 sm:p-8">
        {error ? (
          <>
            <h2 className="text-[22px] font-bold">{t.forgotTitle}</h2>
            <p className="mt-2 text-sm text-subtle">{error}</p>
            <p className="mt-5 text-center text-xs">
              <Link to="/login" className="text-accent">
                {t.signIn}
              </Link>
            </p>
          </>
        ) : recovery ? (
          <>
            <h2 className="text-[22px] font-bold">{t.setNew}</h2>
            <form onSubmit={onSave} className="mt-6 space-y-4">
              <div>
                <FieldLabel>{t.newPassword}</FieldLabel>
                <Input type="password" value={next} onChange={(e) => setNext(e.target.value)} />
              </div>
              <div>
                <FieldLabel>{t.repeatPassword}</FieldLabel>
                <Input type="password" value={repeat} onChange={(e) => setRepeat(e.target.value)} />
              </div>
              <Button type="submit" className="w-full" disabled={busy}>
                {t.savePassword}
              </Button>
            </form>
          </>
        ) : (
          <p className="text-sm text-subtle">{t.confirming}</p>
        )}
      </div>
    </div>
  );
}
