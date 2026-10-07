import { useEffect, useState } from "react";
import { Navigate, Outlet } from "@tanstack/react-router";
import { usePlatform } from "@/lib/platform/store";
import { pullCloudBook } from "@/lib/supabase/books";
import { currentProfile, ensureCloudProfile } from "@/lib/supabase/auth";
import { BottomNav } from "./bottom-nav";
import { Header } from "./header";
import { SideMenu } from "./side-menu";
import { ToastHost } from "./toast";

export function useHydratePlatform() {
  const setHydrated = usePlatform((s) => s.setHydrated);

  useEffect(() => {
    const persist = usePlatform.persist;
    const finish = () => {
      void (async () => {
        const s = usePlatform.getState();
        if (s.sessionOnly && sessionStorage.getItem("lb-session") !== "1") {
          usePlatform.setState({ user: null });
        }
        const profile = await currentProfile();
        if (profile) {
          await ensureCloudProfile(profile);
          usePlatform.getState().setUserProfile(profile);
        }
        const remote = await pullCloudBook();
        const state = usePlatform.getState();
        if (remote && state.user) {
          usePlatform.setState({ ...remote, tickets: remote.tickets ?? [] });
        }
        setHydrated(true);
      })();
    };
    if (persist.hasHydrated()) {
      finish();
      return () => undefined;
    }
    const unsub = persist.onFinishHydration(finish);
    void persist.rehydrate();
    return () => {
      unsub();

    };
  }, [setHydrated]);
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
        <div className="animate-pulse text-base font-semibold tracking-wide">
          Loading Global Beldex<span className="inline-block animate-bounce">...</span>
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
    </div>
  );
}
