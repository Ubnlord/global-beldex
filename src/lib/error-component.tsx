import type { ErrorComponentProps } from "@tanstack/react-router";
import { useEffect } from "react";
import { TriangleAlert } from "lucide-react";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";

export function AppErrorComponent({ error }: ErrorComponentProps) {
  const p = copy[usePlatform((s) => s.lang)].page;
  const message =
    error instanceof Error && error.message
      ? error.message
      : typeof error === "string" && error
        ? error
        : p.errorFallback;

  useEffect(() => {
    if (typeof window === "undefined") return;

    const isChunkFailure =
      message.includes("Failed to fetch dynamically imported module") ||
      message.includes("Importing a module script failed") ||
      message.includes("ChunkLoadError");

    if (!isChunkFailure) return;

    // GitHub Pages replaces hashed assets on each deployment. A user can keep
    // an older SPA shell in the browser cache that points at a chunk that no
    // longer exists. TanStack Router renders this error inside React, so the
    // global recovery listener in __root.tsx is not guaranteed to see it.
    // Force one fresh document request for the current route.
    const marker = "__gb_reload";
    const url = new URL(window.location.href);
    if (url.searchParams.has(marker)) return;

    url.searchParams.set(marker, String(Date.now()));
    window.location.replace(url.toString());
  }, [message]);

  return (
    <main
      className={
        "flex min-h-screen flex-col items-center justify-center gap-3 px-6 text-center " +
        "bg-zinc-50 text-zinc-900 dark:bg-zinc-950 dark:text-zinc-50"
      }
    >
      <span className="text-red-500" aria-hidden="true">
        <TriangleAlert className="size-10" strokeWidth={2} />
      </span>
      <h1 className="text-lg font-semibold">{p.errorTitle}</h1>
      <p className="max-w-md text-sm break-words text-zinc-500 dark:text-zinc-400">
        {message}
      </p>
    </main>
  );
}
