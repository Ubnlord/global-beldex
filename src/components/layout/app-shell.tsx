import { useEffect, useState } from "react";
import { Navigate, Outlet } from "@tanstack/react-router";
import { usePlatform } from "@/lib/platform/store";
import { pullCloudBook, scheduleCloudSave } from "@/lib/supabase/books";
import { currentProfile } from "@/lib/supabase/auth";
import { BottomNav } from "./bottom-nav";
import { Header } from "./header";
import { SideMenu } from "./side-menu";
import { ToastHost } from "./toast";

export function useHydratePlatform() {
  const setHydrated = usePlatform((s) => s.setHydrated);
  const settlePlans = usePlatform((s) => s.settlePlans);

  useEffect(() => {
    const persist = usePlatform.persist;
    const finish = () => {
      void (async () => {
        const s = usePlatform.getState();
        if (s.sessionOnly && sessionStorage.getItem("lb-session") !== "1") {
          usePlatform.setState({ user: null });
        }
        const profile = await currentProfile();
        if (profile) usePlatform.getState().enterAccount(profile);
        const remote = await pullCloudBook();
        const state = usePlatform.getState();
        if (remote && state.user) {
          const email = state.user.email.toLowerCase();
          const rec = state.accounts[email];
          usePlatform.setState({
            ...remote,
            tickets: remote.tickets ?? [],
            accounts: rec
              ? { ...state.accounts, [email]: { ...rec, book: remote } }
              : state.accounts,
          });
        } else if (state.user) {
          scheduleCloudSave({
            available: state.available,
            bdx: state.bdx,
            locked: state.locked,
            profit: state.profit,
            bonus: state.bonus,
            referralBonus: state.referralBonus,
            withdrawn: state.withdrawn,
            txs: state.txs,
            plans: state.plans,
            notices: state.notices,
            tickets: state.tickets ?? [],
          });
        }
        setHydrated(true);
        settlePlans();
        usePlatform.getState().settlePending();
      })();
    };
    const tick = window.setInterval(() => {
      usePlatform.getState().settlePending();
      usePlatform.getState().settlePlans();
    }, 1000);
    if (persist.hasHydrated()) {
      finish();
      return () => window.clearInterval(tick);
    }
    const unsub = persist.onFinishHydration(finish);
    void persist.rehydrate();
    return () => {
      unsub();
      window.clearInterval(tick);
    };
  }, [setHydrated, settlePlans]);
}

export function GuestShell({ children }: { children: React.ReactNode }) {
  useHydratePlatform();
  const [menu, setMenu] = useState(false);
  const user = usePlatform((s) => s.user);
  const hydrated = usePlatform((s) => s.hydrated);

  useEffect(() => {
    const onErr = (z: ErrorEvent) => {
      const src = String((z.target as HTMLElement | null)?.getAttribute?.("src") || "");
      const msg = z.message || "";
      if (src.includes("tradingview.com") || msg.includes("tradingview")) {
        z.preventDefault?.();
        return true;
      }
      return false;
    };
    window.addEventListener("error", onErr, true);
    return () => window.removeEventListener("error", onErr, true);
  }, []);

  return (
    <div className="min-h-screen bg-bg text-fg font-sans">
      <Header onMenu={hydrated && user ? () => setMenu(true) : undefined} />
      {children}
      <SideMenu open={menu} onClose={() => setMenu(false)} />
      <ToastHost />
    </div>
  );
}

export function AppShell() {
  useHydratePlatform();
  const [menu, setMenu] = useState(false);
  const user = usePlatform((s) => s.user);
  const hydrated = usePlatform((s) => s.hydrated);

  useEffect(() => {
    const onErr = (z: ErrorEvent) => {
      const src = String((z.target as HTMLElement | null)?.getAttribute?.("src") || "");
      const msg = z.message || "";
      if (src.includes("tradingview.com") || msg.includes("tradingview")) {
        z.preventDefault?.();
        return true;
      }
      return false;
    };
    window.addEventListener("error", onErr, true);
    return () => window.removeEventListener("error", onErr, true);
  }, []);

  if (!hydrated) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-bg text-muted">
        Loading workspace…
      </div>
    );
  }
  if (!user) return <Navigate to="/login" />;

  return (
    <div className="min-h-screen bg-bg text-fg font-sans">
      <Header onMenu={() => setMenu(true)} />
      <Outlet />
      <BottomNav onMenu={() => setMenu(true)} />
      <SideMenu open={menu} onClose={() => setMenu(false)} />
      <ToastHost />
    </div>
  );
}
