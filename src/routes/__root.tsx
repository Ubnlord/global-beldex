import { createRootRoute, HeadContent, Outlet, Scripts } from "@tanstack/react-router";
import { useEffect } from "react";
import { AuthProvider } from "@/lib/auth/provider";
import { PreviewHostBridge } from "@/components/preview-host-bridge";
import appCss from "../styles.css?url";

const APP_NAME = "GLOBAL BELDEX";

function DynamicImportRecovery() {
  useEffect(() => {
    const recover = () => {
      if (typeof window === "undefined") return;

      const key = "__global_beldex_chunk_recovery";
      const now = Date.now();
      let lastRecovery = 0;

      try {
        lastRecovery = Number(sessionStorage.getItem(key) || "0");
      } catch {
        // Storage can be unavailable in private/restricted browser contexts.
      }

      // A deployment can replace hashed JS chunks while an older page is still open.
      // If navigation then requests the removed chunk, load a fresh document once.
      if (now - lastRecovery < 30000) return;

      try {
        sessionStorage.setItem(key, String(now));
      } catch {
        // Continue with a one-time URL cache-busting reload.
      }

      const url = new URL(window.location.href);
      url.searchParams.set("__gb_reload", String(now));
      window.location.replace(url.toString());
    };

    const onError = (event: ErrorEvent) => {
      // Module-script load errors often expose only a generic event.error while
      // the useful browser message is in event.message. Keep both signals.
      const message = [event.error?.message, event.message]
        .filter(Boolean)
        .join(" ");
      const failedModuleScript =
        event.target instanceof HTMLScriptElement &&
        event.target.type === "module";
      if (
        failedModuleScript ||
        message.includes("Failed to fetch dynamically imported module") ||
        message.includes("Importing a module script failed") ||
        message.includes("ChunkLoadError")
      ) {
        recover();
      }
    };

    const onUnhandledRejection = (event: PromiseRejectionEvent) => {
      const message = String(
        event.reason?.message || event.reason || "",
      );
      if (
        message.includes("Failed to fetch dynamically imported module") ||
        message.includes("Importing a module script failed") ||
        message.includes("ChunkLoadError")
      ) {
        recover();
      }
    };

    window.addEventListener("error", onError);
    window.addEventListener("unhandledrejection", onUnhandledRejection);

    return () => {
      window.removeEventListener("error", onError);
      window.removeEventListener("unhandledrejection", onUnhandledRejection);
    };
  }, []);

  return null;
}

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1, viewport-fit=cover" },
      { title: APP_NAME },
      {
        name: "description",
        content:
          "GLOBAL BELDEX advanced investment platform with live BDXUSD market data from TradingView.",
      },
      { name: "theme-color", content: "#0A0A18" },
    ],
    links: [
      { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" },
      { rel: "stylesheet", href: appCss },
      { rel: "manifest", href: "/__grok/manifest.webmanifest" },
      { rel: "apple-touch-icon", href: "/__grok/icon-180.png" },
      {
        rel: "stylesheet",
        href: "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap",
      },
    ],
  }),
  component: () => (
    <html lang="en" suppressHydrationWarning>
      <head>
        <HeadContent />
      </head>
      <body>
        <PreviewHostBridge />
        <DynamicImportRecovery />
        <AuthProvider>
          <Outlet />
        </AuthProvider>
        <Scripts />
      </body>
    </html>
  ),
});
