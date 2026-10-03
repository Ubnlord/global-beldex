import { ArrowDownToLine, ArrowUpFromLine, History, Home, Menu } from "lucide-react";
import { Link, useRouterState } from "@tanstack/react-router";
import { cn } from "@/lib/utils";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";

const ITEMS = [
  { id: "history", to: "/app/history", labelKey: "history" as const, icon: History },
  { id: "deposit", to: "/app/deposit", labelKey: "deposit" as const, icon: ArrowDownToLine },
  { id: "dashboard", to: "/app", labelKey: "home" as const, icon: Home, center: true },
  { id: "withdraw", to: "/app/withdraw", labelKey: "withdraw" as const, icon: ArrowUpFromLine },
  { id: "menu", to: "menu", labelKey: "menu" as const, icon: Menu },
];

export function BottomNav({ onMenu }: { onMenu: () => void }) {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];

  return (
    <nav className="fixed inset-x-0 bottom-0 z-20 border-t border-line bg-surface pb-[env(safe-area-inset-bottom)]">
      <div className="mx-auto flex h-[76px] max-w-[520px] items-end justify-between px-1 pb-2">
        {ITEMS.map((item) => {
          const active =
            item.to === "/app"
              ? pathname === "/app" || pathname === "/app/"
              : item.id !== "menu" && pathname.startsWith(item.to);
          const Icon = item.icon;
          const label = t[item.labelKey];
          if (item.center) {
            return (
              <Link
                key={item.id}
                to="/app"
                className="-mt-5 flex w-[72px] shrink-0 flex-col items-center gap-1"
              >
                <div
                  className={cn(
                    "flex size-14 items-center justify-center rounded-full border-4 border-bg shadow-lg transition-colors",
                    active ? "bg-accent text-accent-fg" : "bg-elevated text-subtle",
                  )}
                >
                  <Icon size={22} />
                </div>
                <span
                  className={cn(
                    "max-w-[72px] truncate text-center text-[10px] leading-none",
                    active ? "font-semibold text-accent" : "text-subtle",
                  )}
                >
                  {label}
                </span>
              </Link>
            );
          }
          const className = "flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-1 pb-0.5";
          const icon = <Icon size={18} className={active ? "text-accent" : "text-subtle"} />;
          const caption = (
            <span
              className={cn(
                "w-full truncate px-0.5 text-center text-[10px] leading-none",
                active ? "font-medium text-accent" : "text-subtle",
              )}
            >
              {label}
            </span>
          );
          if (item.id === "menu") {
            return (
              <button key={item.id} type="button" onClick={onMenu} className={className}>
                {icon}
                {caption}
              </button>
            );
          }
          return (
            <Link key={item.id} to={item.to} className={className}>
              {icon}
              {caption}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}