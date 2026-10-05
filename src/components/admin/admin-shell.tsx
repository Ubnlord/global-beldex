import { Link, useNavigate } from "@tanstack/react-router";
import { LayoutDashboard, LogOut, Menu, ShieldCheck, Users, Wallet, X } from "lucide-react";
import { useState } from "react";
import { Mark } from "@/components/brand/logo";
import { signOutCloud } from "@/lib/supabase/auth";
import { usePlatform } from "@/lib/platform/store";

export function AdminShell({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const user = usePlatform((s) => s.user);
  const [open, setOpen] = useState(false);

  async function logout() {
    await signOutCloud();
    usePlatform.setState({ user: null });
    setOpen(false);
    void navigate({ to: "/admin/login", replace: true });
  }

  return (
    <div className="min-h-screen bg-[#070812] text-slate-100">
      <div className="flex min-h-screen">
        <aside className="hidden w-[250px] shrink-0 border-r border-white/10 bg-[#0b0d1b] lg:flex lg:flex-col">
          <AdminBrand />
          <AdminNav />
          <div className="mt-auto border-t border-white/10 p-4">
            <AdminUser email={user?.email} />
            <SignOutButton onClick={() => void logout()} />
          </div>
        </aside>

        {open && (
          <div className="fixed inset-0 z-[100] lg:hidden">
            <button aria-label="Close admin menu" className="absolute inset-0 bg-black/70" onClick={() => setOpen(false)} />
            <aside className="relative flex h-full w-[285px] flex-col border-r border-white/10 bg-[#0b0d1b] shadow-2xl">
              <div className="flex items-center justify-between border-b border-white/10 p-5">
                <AdminBrand compact />
                <button type="button" onClick={() => setOpen(false)} className="rounded-lg p-2 text-slate-400 hover:bg-white/5 hover:text-white" aria-label="Close">
                  <X size={20} />
                </button>
              </div>
              <AdminNav onNavigate={() => setOpen(false)} />
              <div className="mt-auto border-t border-white/10 p-4">
                <AdminUser email={user?.email} />
                <SignOutButton onClick={() => void logout()} />
              </div>
            </aside>
          </div>
        )}

        <main className="min-w-0 flex-1">
          <header className="sticky top-0 z-40 flex h-[72px] items-center justify-between border-b border-white/10 bg-[#070812]/95 px-4 backdrop-blur lg:px-8">
            <div className="flex items-center gap-3">
              <button type="button" onClick={() => setOpen(true)} className="rounded-xl border border-white/10 bg-white/5 p-2.5 text-slate-300 lg:hidden" aria-label="Open admin menu">
                <Menu size={20} />
              </button>
              <div className="flex items-center gap-2.5 lg:hidden">
                <Mark className="size-8" />
                <div>
                  <div className="text-sm font-bold tracking-tight">GLOBAL BELDEX</div>
                  <div className="text-[9px] font-semibold uppercase tracking-[0.18em] text-[#28e6d0]">Admin Console</div>
                </div>
              </div>
              <div className="hidden items-center gap-2 lg:flex">
                <ShieldCheck size={18} className="text-[#28e6d0]" />
                <span className="text-sm font-semibold text-slate-300">Administrator Console</span>
              </div>
            </div>
            <div className="flex items-center gap-2 rounded-full border border-[#28e6d0]/20 bg-[#28e6d0]/5 px-3 py-1.5 text-[10px] font-bold uppercase tracking-wider text-[#28e6d0]">
              <span className="size-1.5 rounded-full bg-[#28e6d0]" /> Secure Admin
            </div>
          </header>
          <div className="mx-auto max-w-[1500px] p-4 sm:p-6 lg:p-8">{children}</div>
        </main>
      </div>
    </div>
  );
}

function AdminBrand({ compact = false }: { compact?: boolean }) {
  return (
    <div className={compact ? "flex items-center gap-3" : "border-b border-white/10 p-5"}>
      <div className="flex items-center gap-3">
        <Mark className="size-10" />
        <div>
          <div className="font-bold tracking-tight text-white">GLOBAL BELDEX</div>
          <div className="mt-1 text-[9px] font-semibold uppercase tracking-[0.2em] text-[#28e6d0]">Administrator</div>
        </div>
      </div>
    </div>
  );
}

function AdminNav({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <nav className="space-y-1 p-4">
      <AdminLink to="/admin" icon={LayoutDashboard} onNavigate={onNavigate}>Dashboard</AdminLink>
      <AdminLink to="/admin" icon={Wallet} onNavigate={onNavigate}>Transactions</AdminLink>
      <AdminLink to="/admin" icon={Users} onNavigate={onNavigate}>Users & KYC</AdminLink>
    </nav>
  );
}

function AdminLink({ to, icon: Icon, children, onNavigate }: { to: "/admin"; icon: typeof LayoutDashboard; children: React.ReactNode; onNavigate?: () => void }) {
  return (
    <Link
      to={to}
      onClick={onNavigate}
      activeOptions={{ exact: true }}
      activeProps={{ className: "flex items-center gap-3 rounded-xl bg-[#28e6d0]/10 px-3 py-3 text-sm font-semibold text-[#28e6d0]" }}
      className="flex items-center gap-3 rounded-xl px-3 py-3 text-sm text-slate-400 transition hover:bg-white/5 hover:text-white"
    >
      <Icon size={18} /> {children}
    </Link>
  );
}

function AdminUser({ email }: { email?: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.03] p-3">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-slate-500">Signed in as</div>
      <div className="mt-1 truncate text-xs font-medium text-slate-200">{email || "Administrator"}</div>
    </div>
  );
}

function SignOutButton({ onClick }: { onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="mt-3 flex w-full items-center gap-3 rounded-xl px-3 py-3 text-sm text-slate-400 transition hover:bg-white/5 hover:text-white">
      <LogOut size={17} /> Sign out
    </button>
  );
}
