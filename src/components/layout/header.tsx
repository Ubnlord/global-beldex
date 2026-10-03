import { Bell } from "lucide-react";
import { Link, useNavigate, useRouterState } from "@tanstack/react-router";
import { BrandLockup } from "@/components/brand/logo";
import { Avatar } from "@/components/layout/avatar";
import { Button } from "@/components/ui/button";
import { copy, LANGS, type Lang } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";

export function Header({ onMenu }: { onMenu?: () => void }) {
  const navigate = useNavigate();
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const user = usePlatform((s) => s.user);
  const lang = usePlatform((s) => s.lang);
  const setLang = usePlatform((s) => s.setLang);
  const notices = usePlatform((s) => s.notices);
  const t = copy[lang];
  const unread = notices.filter((n) => !n.read).length;

  return (
    <header className="sticky top-0 z-30 border-b border-line bg-bg/95 backdrop-blur-xl pt-[env(safe-area-inset-top)]">
      <div className="mx-auto flex h-14 max-w-[1200px] items-center justify-between gap-2 px-3 sm:h-16 sm:px-6">
        <BrandLockup
          to={user ? "/app" : "/"}
          subtitle={t.tag}
        />
        <div className="flex shrink-0 items-center gap-1.5 sm:gap-3">
          <select
            value={lang}
            onChange={(e) => setLang(e.target.value as Lang)}
            aria-label="Language"
            className="h-9 rounded-full border border-line-strong bg-surface px-2 text-xs text-fg outline-none"
          >
            {LANGS.map((item) => (
              <option key={item.id} value={item.id}>
                {item.short}
              </option>
            ))}
          </select>
          {user ? (
            <>
              <Link
                to="/app/notifications"
                className="relative flex size-9 items-center justify-center rounded-full border border-line-strong bg-elevated text-muted"
                aria-label="Notifications"
              >
                <Bell size={16} />
                {unread > 0 && (
                  <span className="absolute -right-0.5 -top-0.5 flex size-4 items-center justify-center rounded-full bg-accent text-[9px] font-bold text-accent-fg">
                    {unread > 9 ? "9+" : unread}
                  </span>
                )}
              </Link>
              <button
                type="button"
                onClick={onMenu}
                className="flex size-9 items-center justify-center overflow-hidden rounded-full bg-accent text-xs font-bold text-accent-fg"
                aria-label="Open menu"
              >
                <Avatar name={user.name} src={user.avatar} className="size-9 text-xs" />
              </button>
            </>
          ) : (
            <div className="hidden items-center gap-2 sm:flex">
              {pathname !== "/login" && (
                <Button variant="ghost" size="sm" onClick={() => navigate({ to: "/login" })}>
                  {t.signIn}
                </Button>
              )}
              {pathname !== "/register" && (
                <Button size="sm" onClick={() => navigate({ to: "/register" })}>
                  {t.openAccount}
                </Button>
              )}
            </div>
          )}
        </div>
      </div>
      {!user && (
        <div className="flex gap-2 px-3 pb-3 sm:hidden">
          {pathname !== "/login" && (
            <Button variant="secondary" size="sm" className="flex-1" onClick={() => navigate({ to: "/login" })}>
              {t.signIn}
            </Button>
          )}
          {pathname !== "/register" && (
            <Button size="sm" className="flex-1" onClick={() => navigate({ to: "/register" })}>
              {t.openAccount}
            </Button>
          )}
        </div>
      )}
    </header>
  );
}
