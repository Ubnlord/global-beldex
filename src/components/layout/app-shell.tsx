import { useEffect, useState } from "react";
import { RotateCw } from "lucide-react";
import { Navigate, Outlet } from "@tanstack/react-router";
import { usePlatform } from "@/lib/platform/store";
import { pullCloudBook } from "@/lib/supabase/books";
import { currentProfile } from "@/lib/supabase/auth";
import { BottomNav } from "./bottom-nav";
import { Header } from "./header";
import { SideMenu } from "./side-menu";
import { ToastHost } from "./toast";
import { RobotAssistant } from "./robot-assistant";
import { useRealtimeUserNotifications } from "@/lib/supabase/realtime-notifications";

export function useHydratePlatform() {
  const setHydrated = usePlatform((s) => s.setHydrated);
  const user = usePlatform((s) => s.user);
  const settlePlans = usePlatform((s) => s.settlePlans);

  useEffect(() => {
    const persist = usePlatform.persist;
    let cancelled = false;
    const finish = () => {
      void (async () => {
        try {
          const s = usePlatform.getState();
          if (s.sessionOnly && sessionStorage.getItem("lb-session") !== "1") {
            usePlatform.setState({ user: null });
          }
          const profile = await currentProfile();
          if (profile) {
            // A profile-sync failure should not prevent the app from finishing hydration.
            // The saved account figures remain in place until a full cloud refresh succeeds.
            // Never create/upsert a profile during ordinary hydration: a missing
            // server profile must remain visible as a recovery condition, not be
            // silently recreated (which can also trigger a welcome-bonus mutation).
            usePlatform.getState().setUserProfile(profile);
          }
          const remote = await pullCloudBook();
          const state = usePlatform.getState();
          if (remote && state.user) {
            usePlatform.setState({
              ...remote,
              tickets: remote.tickets ?? [],
              accrualFailed: remote.accrualFailed,
            });
          } else if (state.user) {
            // Keep the last known financial figures, but make the failed cloud refresh visible.
            usePlatform.setState({ accrualFailed: true });
          }
        } catch {
          // Network or unexpected auth/profile errors must not leave the app on its loading screen.
          // Do not replace cached financial values with zeroes when refresh fails.
          if (usePlatform.getState().user) {
            usePlatform.setState({ accrualFailed: true });
          }
        } finally {
          if (!cancelled) setHydrated(true);
        }
      })();
    };
    if (persist.hasHydrated()) {
      finish();
      return () => {
        cancelled = true;
      };
    }
    const unsub = persist.onFinishHydration(finish);
    void persist.rehydrate();
    return () => {
      cancelled = true;
      unsub();
    };
  }, [setHydrated]);

  // Keep the server-authoritative daily accrual current while an authenticated
  // session is open. The RPC only credits complete elapsed days and is idempotent.
  useEffect(() => {
    if (!user) return;
    let running = false;
    const refresh = async () => {
      if (running || document.visibilityState === "hidden") return;
      running = true;
      try {
        await settlePlans();
      } finally {
        running = false;
      }
    };
    const timer = window.setInterval(() => void refresh(), 60_000);
    const onVisible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onVisible);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onVisible);
    };
  }, [user, settlePlans]);
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
      <RobotAssistant />
    </div>
  );
}

export function AppShell() {
  useHydratePlatform();
  useRealtimeUserNotifications();
  const [menu, setMenu] = useState(false);
  const user = usePlatform((s) => s.user);
  const hydrated = usePlatform((s) => s.hydrated);
  const accrualFailed = usePlatform((s) => s.accrualFailed);
  const available = usePlatform((s) => s.available);
  const bdx = usePlatform((s) => s.bdx);
  const locked = usePlatform((s) => s.locked);
  const profit = usePlatform((s) => s.profit);
  const txs = usePlatform((s) => s.txs);
  const plans = usePlatform((s) => s.plans);
  const settlePlans = usePlatform((s) => s.settlePlans);
  const [retryingFinancialRefresh, setRetryingFinancialRefresh] = useState(false);
  // On a cold start, a failed cloud read leaves the store's initial empty book.
  // Do not render those placeholder zeroes as if they were authoritative balances.
  const financialBookUnavailable = Boolean(user && accrualFailed &&
    available === 0 && bdx === 0 && locked === 0 && profit === 0 &&
    txs.length === 0 && plans.length === 0);

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
        <div className="flex flex-col items-center">
          <RotateCw
            size={34}
            strokeWidth={2.5}
            className="mb-3 animate-spin text-accent"
            aria-hidden="true"
          />
          <div className="animate-pulse text-base font-semibold tracking-wide">
            Loading Global Beldex<span className="inline-block animate-bounce">...</span>
          </div>
        </div>
      </div>
    );
  }
  if (!user) return <Navigate to="/login" replace />;

  if (financialBookUnavailable) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-bg px-4 text-fg">
        <div className="w-full max-w-md rounded-xl border border-amber-500/40 bg-surface p-6">
          <h1 className="text-lg font-bold">Your financial records aren't available yet</h1>
          <p className="mt-2 text-sm text-subtle">
            We couldn't verify your latest account balances. To protect your records,
            we won't display placeholder zeroes. Your saved server-side records have not
            been changed by this failed refresh.
          </p>
          <button
            type="button"
            disabled={retryingFinancialRefresh}
            onClick={async () => {
              setRetryingFinancialRefresh(true);
              try {
                await settlePlans();
              } finally {
                setRetryingFinancialRefresh(false);
              }
            }}
            className="mt-5 w-full rounded-lg bg-accent px-4 py-3 text-sm font-semibold text-black disabled:opacity-60"
          >
            {retryingFinancialRefresh ? "Checking account…" : "Retry account refresh"}
          </button>
          <p className="mt-3 text-xs text-subtle">
            If this continues, contact support before making any financial decisions.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-bg text-fg font-sans">
      <Header onMenu={() => setMenu(true)} />
      <Outlet />
      <BottomNav onMenu={() => setMenu(true)} />
      <SideMenu open={menu} onClose={() => setMenu(false)} />
      <ToastHost />
      <RobotAssistant />
    </div>
  );
}
