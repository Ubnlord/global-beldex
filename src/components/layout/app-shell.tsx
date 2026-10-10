import { useEffect, useState } from "react";
import { RotateCw } from "lucide-react";
import { toastError } from "@/components/layout/toast";
import { Navigate, Outlet } from "@tanstack/react-router";
import { usePlatform } from "@/lib/platform/store";
import { pullCloudBook } from "@/lib/supabase/books";
import { currentProfile, ensureCloudProfile } from "@/lib/supabase/auth";
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
        let refreshFailed = false;
        try {
          const s = usePlatform.getState();
          if (s.sessionOnly && sessionStorage.getItem("lb-session") !== "1") {
            usePlatform.setState({ user: null });
          }
          const profile = await currentProfile();
          if (profile) {
            // A profile-sync failure should not prevent the app from finishing hydration.
            // The saved account figures remain in place until a full cloud refresh succeeds.
            const profileError = await ensureCloudProfile(profile);
            if (profileError) {
              refreshFailed = true;
              usePlatform.setState({ accrualFailed: true });
              toastError(`We couldn't sync your account profile: ${profileError}`);
            } else {
              usePlatform.getState().setUserProfile(profile);
            }
          }
          const remote = await pullCloudBook();
          const state = usePlatform.getState();
          if (remote && state.user) {
            usePlatform.setState({
              ...remote,
              tickets: remote.tickets ?? [],
              accrualFailed: refreshFailed || remote.accrualFailed,
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
