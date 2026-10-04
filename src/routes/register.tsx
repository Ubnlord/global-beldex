import { createFileRoute, Link, Navigate, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, type FormEvent } from "react";
import { GuestShell } from "@/components/layout/app-shell";
import { toast, toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { COUNTRIES } from "@/lib/platform/catalog";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { signUpAccount } from "@/lib/supabase/auth";

export const Route = createFileRoute("/register")({ component: RegisterPage });

function RegisterPage() {
  return (
    <GuestShell>
      <Register />
    </GuestShell>
  );
}

function Register() {
  const navigate = useNavigate();
  const register = usePlatform((s) => s.register);
  const enterAccount = usePlatform((s) => s.enterAccount);
  const user = usePlatform((s) => s.user);
  const hydrated = usePlatform((s) => s.hydrated);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [form, setForm] = useState({
    username: "",
    fullname: "",
    email: "",
    phone: "",
    country: "",
    ref: "",
    pass: "",
    repeat: "",
  });
  const [pendingEmail, setPendingEmail] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const ref = new URLSearchParams(window.location.search).get("ref")?.trim();
    if (!ref) return;
    setForm((current) => (current.ref ? current : { ...current, ref }));
  }, []);

  const set = (k: keyof typeof form, v: string) => setForm((s) => ({ ...s, [k]: v }));

  if (hydrated && user) return <Navigate to="/app" />;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (form.pass !== form.repeat) {
      toast(t.mismatch);
      return;
    }
    if (form.pass.length < 6) {
      toast(t.shortPass);
      return;
    }
    setBusy(true);
    const result = await signUpAccount({
      email: form.email,
      username: form.username,
      fullname: form.fullname,
      phone: form.phone,
      country: form.country,
      ref: form.ref,
      pass: form.pass,
    });
    setBusy(false);
    if (result.error) {
      toast(result.error);
      return;
    }
    if (result.needsConfirm) {
      setPendingEmail(form.email.trim());
      return;
    }
    const err = result.profile ? enterAccount(result.profile) : register(form);
    if (err) {
      toastError(err);
      return;
    }
    toast(t.created);
    void navigate({ to: "/app" });
  };

  if (pendingEmail) {
    return (
      <div className="flex min-h-[calc(100vh-64px)] items-center justify-center px-4 py-10">
        <div className="w-full max-w-[480px] rounded-xl border border-line bg-surface p-6 sm:p-8">
          <h2 className="text-[22px] font-bold">{t.checkEmailTitle}</h2>
          <p className="mt-2 text-[13px] text-subtle">{t.checkEmailBody}</p>
          <p className="mt-4 break-all text-sm font-semibold text-fg">{pendingEmail}</p>
          <p className="mt-5 text-center text-xs text-subtle">
            <Link to="/login" className="font-medium text-accent">
              {t.signIn}
            </Link>
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-[calc(100vh-64px)] items-center justify-center px-4 py-10">
      <div className="w-full max-w-[480px] rounded-xl border border-line bg-surface p-6 sm:p-8">
        <h2 className="text-[22px] font-bold">{t.createTitle}</h2>
        <p className="mt-1 text-[13px] text-subtle">{t.createLead}</p>
        <form onSubmit={onSubmit} className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <FieldLabel>{t.username}</FieldLabel>
            <Input
              value={form.username}
              onChange={(e) => set("username", e.target.value)}
              placeholder="johnbeldex"
            />
          </div>
          <div>
            <FieldLabel>{t.fullname}</FieldLabel>
            <Input
              value={form.fullname}
              onChange={(e) => set("fullname", e.target.value)}
              placeholder="Kelvin Copeland"
            />
          </div>
          <div>
            <FieldLabel>{t.email}</FieldLabel>
            <Input
              type="email"
              value={form.email}
              onChange={(e) => set("email", e.target.value)}
              placeholder="you@mail.com"
            />
          </div>
          <div>
            <FieldLabel>{t.phone}</FieldLabel>
            <Input
              value={form.phone}
              onChange={(e) => set("phone", e.target.value)}
              placeholder="+1 ..."
            />
          </div>
          <div>
            <FieldLabel>{t.country}</FieldLabel>
            <select
              value={form.country}
              onChange={(e) => set("country", e.target.value)}
              className="mt-1 w-full rounded-md border border-line-strong bg-elevated px-4 py-3 text-sm text-muted outline-none focus:border-accent"
            >
              <option value="">{t.selectCountry}</option>
              {COUNTRIES.map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
          </div>
          <div>
            <FieldLabel>{t.referralOptional}</FieldLabel>
            <Input
              value={form.ref}
              onChange={(e) => set("ref", e.target.value)}
              placeholder="REF123"
            />
          </div>
          <div>
            <FieldLabel>{t.password}</FieldLabel>
            <Input
              type="password"
              value={form.pass}
              onChange={(e) => set("pass", e.target.value)}
              placeholder="••••••••"
            />
          </div>
          <div>
            <FieldLabel>{t.repeatPassword}</FieldLabel>
            <Input
              type="password"
              value={form.repeat}
              onChange={(e) => set("repeat", e.target.value)}
              placeholder="••••••••"
            />
          </div>
          <div className="sm:col-span-2">
            <p className="text-[11px] text-subtle">
              {t.acceptLead}
              <Link to="/legal" hash="terms" className="text-accent">
                {t.termsWord}
              </Link>
              {", "}
              <Link to="/legal" hash="privacy" className="text-accent">
                {t.privacyWord}
              </Link>
              {t.acceptAnd}
              <Link to="/legal" hash="risk" className="text-accent">
                {t.riskWord}
              </Link>
              {t.acceptTail}
            </p>
            <Button type="submit" className="mt-3 w-full" disabled={busy}>
              {busy ? "…" : t.createBtn}
            </Button>
          </div>
        </form>
        <p className="mt-5 text-center text-xs text-subtle">
          {t.haveAccount}{" "}
          <Link to="/login" className="font-medium text-accent">
            {t.signIn}
          </Link>
        </p>
      </div>
    </div>
  );
}
