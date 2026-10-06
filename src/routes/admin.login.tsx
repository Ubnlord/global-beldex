import { createFileRoute, Link, Navigate, useNavigate } from "@tanstack/react-router";
import { Eye, EyeOff, ShieldCheck } from "lucide-react";
import { useState, type FormEvent } from "react";
import { GuestShell } from "@/components/layout/app-shell";
import { toast } from "@/components/layout/toast";
import { Mark } from "@/components/brand/logo";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { usePlatform } from "@/lib/platform/store";
import { signInAccount, signOutCloud } from "@/lib/supabase/auth";
import { supabase } from "@/lib/supabase/client";

export const Route = createFileRoute("/admin/login")({ component: AdminLoginPage });

function AdminLoginPage() {
  return (
    <GuestShell>
      <AdminLogin />
    </GuestShell>
  );
}

function AdminLogin() {
  const navigate = useNavigate();
  const setUserProfile = usePlatform((s) => s.setUserProfile);
  const user = usePlatform((s) => s.user);
  const hydrated = usePlatform((s) => s.hydrated);
  const [email, setEmail] = useState("");
  const [pass, setPass] = useState("");
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  if (hydrated && user) return <Navigate to="/admin" replace />;

  const onSubmit = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setError("");

    const auth = await signInAccount(email, pass);
    if (auth.error || !auth.profile) {
      setBusy(false);
      setError(auth.error || "Unable to sign in.");
      return;
    }

    const {
      data: { user: authUser },
    } = await supabase.auth.getUser();

    if (!authUser) {
      setBusy(false);
      setError("Unable to verify the administrator session.");
      return;
    }

    const { data: admin, error: adminError } = await supabase
      .from("admin_user")
      .select("id,role")
      .eq("user_id", authUser.id)
      .maybeSingle();

    if (adminError || !admin) {
      await signOutCloud();
      setBusy(false);
      setError("This account is not authorized for administrator access.");
      return;
    }

    setUserProfile(auth.profile);
    setBusy(false);
    toast("Administrator access granted.");
    void navigate({ to: "/admin", replace: true });
  };

  return (
    <div className="flex min-h-[calc(100vh-64px)] items-center justify-center px-4 py-10">
      <div className="w-full max-w-[430px] rounded-2xl border border-accent/20 bg-surface p-6 shadow-2xl sm:p-8">
        <div className="mb-7 flex items-center gap-3">
          <Mark className="size-10" />
          <div>
            <div className="font-bold leading-none text-fg">GLOBAL BELDEX</div>
            <div className="mt-1 flex items-center gap-1.5 text-[10px] uppercase tracking-widest text-accent">
              <ShieldCheck size={12} /> Administrator Portal
            </div>
          </div>
        </div>

        <div className="mb-6 rounded-xl border border-accent/20 bg-accent/5 p-4">
          <div className="text-sm font-semibold text-fg">Secure administrator sign in</div>
          <div className="mt-1 text-xs leading-5 text-muted">
            This portal is restricted to accounts listed in the Global Beldex administrator registry.
          </div>
        </div>

        {error && (
          <div
            role="alert"
            className="mb-5 rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-300"
          >
            {error}
          </div>
        )}

        <form onSubmit={onSubmit} className="space-y-4">
          <div>
            <FieldLabel>Administrator email</FieldLabel>
            <Input
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              type="email"
              placeholder="admin@example.com"
              autoComplete="username"
              required
            />
          </div>

          <div>
            <FieldLabel>Administrator password</FieldLabel>
            <div className="relative mt-1">
              <Input
                value={pass}
                onChange={(event) => setPass(event.target.value)}
                type={show ? "text" : "password"}
                placeholder="••••••••"
                autoComplete="current-password"
                className="mt-0 pr-10"
                required
              />
              <button
                type="button"
                onClick={() => setShow((value) => !value)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-subtle"
                aria-label={show ? "Hide password" : "Show password"}
              >
                {show ? <EyeOff size={17} /> : <Eye size={17} />}
              </button>
            </div>
          </div>

          <Button type="submit" className="w-full" disabled={busy}>
            {busy ? "Verifying access…" : "Sign In to Admin"}
          </Button>
        </form>

        <div className="mt-6 flex items-center justify-between text-xs">
          <Link to="/login" className="text-muted hover:text-fg">
            ← User login
          </Link>
          <Link to="/forgot" className="text-accent">
            Forgot password?
          </Link>
        </div>
      </div>
    </div>
  );
}
