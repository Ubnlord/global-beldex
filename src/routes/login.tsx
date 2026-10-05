import { createFileRoute, Link, Navigate, useNavigate } from "@tanstack/react-router";
import { Eye, EyeOff } from "lucide-react";
import { useState, type FormEvent } from "react";
import { GuestShell } from "@/components/layout/app-shell";
import { toast, toastError } from "@/components/layout/toast";
import { Mark } from "@/components/brand/logo";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { copy, LANGS, type Lang } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { signInAccount } from "@/lib/supabase/auth";

export const Route = createFileRoute("/login")({ component: LoginPage });

function LoginPage() {
  return (
    <GuestShell>
      <Login />
    </GuestShell>
  );
}

function Login() {
  const navigate = useNavigate();
  const login = usePlatform((s) => s.login);
  const enterAccount = usePlatform((s) => s.enterAccount);
  const accounts = usePlatform((s) => s.accounts);
  const setSessionOnly = usePlatform((s) => s.setSessionOnly);
  const lang = usePlatform((s) => s.lang);
  const setLang = usePlatform((s) => s.setLang);
  const user = usePlatform((s) => s.user);
  const hydrated = usePlatform((s) => s.hydrated);
  const t = copy[lang];
  const [show, setShow] = useState(false);
  const [email, setEmail] = useState("");
  const [pass, setPass] = useState("");
  const [code, setCode] = useState("");
  const [needCode, setNeedCode] = useState(false);
  const [remember, setRemember] = useState(true);
  const [busy, setBusy] = useState(false);

  if (hydrated && user) return <Navigate to="/app" replace />;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    let identity = email.trim();
    if (identity && !identity.includes("@")) {
      const found = Object.values(accounts).find(
        (a) => a.user.username.toLowerCase() === identity.toLowerCase(),
      );
      if (found) identity = found.user.email;
    }
    setBusy(true);
    const cloud = identity.includes("@") ? await signInAccount(identity, pass) : { error: t.page.badLogin, profile: null };
    setBusy(false);
    if (!cloud.error && cloud.profile) {
      enterAccount(cloud.profile);
      if (!remember) {
        sessionStorage.setItem("lb-session", "1");
        setSessionOnly(true);
      }
      toast(t.welcomeBack);
      void navigate({ to: "/app" });
      return;
    }
    if (cloud.error?.toLowerCase().includes("confirm")) {
      toast(cloud.error);
      return;
    }
    const err = login(email, pass, needCode ? code : undefined);
    if (err === "2FA") {
      setNeedCode(true);
      toast(t.needCode);
      return;
    }
    if (err) {
      if (identity.includes("@") && cloud.error) toast(cloud.error);
      else toastError(err);
      return;
    }
    if (remember) {
      sessionStorage.removeItem("lb-session");
      setSessionOnly(false);
    } else {
      sessionStorage.setItem("lb-session", "1");
      setSessionOnly(true);
    }
    toast(t.welcomeBack);
    void navigate({ to: "/app" });
  };

  return (
    <div className="flex min-h-[calc(100vh-64px)] items-center justify-center px-4 py-10">
      <div className="w-full max-w-[400px] rounded-xl border border-line bg-surface p-6 sm:p-8">
        <div className="mb-6 flex items-center gap-2">
          <Mark className="size-9" />
          <div>
            <div className="font-bold leading-none">GLOBAL BELDEX</div>
            <div className="flex items-center gap-1 text-[10px] text-subtle">
              <span className="size-1.5 rounded-full bg-accent" />
              {t.tag}
            </div>
          </div>
          <select
            value={lang}
            onChange={(e) => setLang(e.target.value as Lang)}
            aria-label="Language"
            className="ml-auto h-9 rounded-full border border-line-strong bg-surface px-2 text-[11px] text-fg outline-none"
          >
            {LANGS.map((item) => (
              <option key={item.id} value={item.id}>
                {item.short}
              </option>
            ))}
          </select>
        </div>
        <h2 className="text-[22px] font-bold">{t.loginTitle}</h2>
        <p className="mt-1 text-[13px] text-subtle">{t.loginLead}</p>
        <form onSubmit={onSubmit} className="mt-6 space-y-4">
          <div>
            <FieldLabel>{t.emailOrUser}</FieldLabel>
            <Input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              autoComplete="username"
            />
          </div>
          <div>
            <FieldLabel>{t.password}</FieldLabel>
            <div className="relative mt-1">
              <Input
                type={show ? "text" : "password"}
                value={pass}
                onChange={(e) => setPass(e.target.value)}
                placeholder="••••••••"
                className="mt-0 pr-10"
                autoComplete="current-password"
              />
              <button
                type="button"
                onClick={() => setShow((v) => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-subtle"
                aria-label="Toggle password"
              >
                {show ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>
          {needCode && (
            <div>
              <FieldLabel>{t.codeLabel}</FieldLabel>
              <Input
                value={code}
                onChange={(e) => setCode(e.target.value)}
                inputMode="numeric"
                placeholder="000000"
                autoComplete="one-time-code"
              />
            </div>
          )}
          <div className="flex items-center justify-between text-xs">
            <label className="flex items-center gap-2 text-muted">
              <input
                type="checkbox"
                className="rounded"
                checked={remember}
                onChange={(e) => setRemember(e.target.checked)}
              />
              {t.remember}
            </label>
            <Link to="/forgot" className="text-accent">
              {t.forgot}
            </Link>
          </div>
          <Button type="submit" className="w-full" disabled={busy}>
            {t.signIn}
          </Button>
        </form>
        <p className="mt-5 text-center text-xs text-subtle">
          {t.notMember}{" "}
          <Link to="/register" className="font-medium text-accent">
            {t.signUp}
          </Link>
        </p>
        <div className="mt-4 text-center">
          <Link
            to="/admin/login"
            className="inline-flex items-center gap-1.5 text-[11px] font-medium text-muted hover:text-accent"
          >
            Administrator Login
          </Link>
        </div>
        <LoginPreview />
      </div>
    </div>
  );
}

function LoginPreview() {
  const lang = usePlatform((s) => s.lang);
  const p = copy[lang].page;
  return (
    <div className="mt-6 overflow-hidden rounded-md border border-line">
      <div className="relative h-[120px] bg-panel">
        <div className="absolute inset-0 opacity-70">
          <div className="h-full w-full bg-[radial-gradient(circle_at_20%_20%,rgba(42,245,212,0.18),transparent_45%),radial-gradient(circle_at_80%_80%,rgba(42,245,212,0.08),transparent_40%)]" />
        </div>
        <div className="relative flex h-full flex-col justify-end p-4">
          <div className="text-[10px] tracking-widest text-accent">{p.dashPreview}</div>
          <div className="text-sm font-semibold">{p.availableTape}</div>
          <div className="text-[11px] text-subtle">{p.signInSim}</div>
        </div>
      </div>
    </div>
  );
}
