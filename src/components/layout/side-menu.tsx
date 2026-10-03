import {
  ArrowDownToLine,
  ArrowUpFromLine,
  Bell,
  History,
  Home,
  LayoutGrid,
  LifeBuoy,
  LineChart,
  LogOut,
  Repeat,
  Settings,
  Shield,
  Users,
  X,
} from "lucide-react";
import { Link, useNavigate } from "@tanstack/react-router";
import { BrandLockup } from "@/components/brand/logo";
import { Avatar } from "@/components/layout/avatar";
import { Button } from "@/components/ui/button";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { signOutCloud } from "@/lib/supabase/auth";
import type { ComponentType } from "react";

export function SideMenu({ open, onClose }: { open: boolean; onClose: () => void }) {
  const user = usePlatform((s) => s.user);
  const logout = usePlatform((s) => s.logout);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const navigate = useNavigate();

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[60] flex">
      <button
        type="button"
        className="flex-1 bg-black/60 backdrop-blur-sm"
        aria-label="Close menu"
        onClick={onClose}
      />
      <aside className="flex h-full w-[min(88vw,320px)] flex-col overflow-y-auto border-l border-line bg-surface pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)]">
        <div className="flex items-start justify-between border-b border-line p-5">
          <div className="flex items-center gap-3">
            <Avatar name={user?.name} src={user?.avatar} className="size-10 text-sm" />
            <div>
              <div className="text-[13px] font-semibold text-fg">
                {user?.name || "Kenneth Munachimso"}
              </div>
              <div className="text-[11px] text-subtle">
                {user?.email || "mrkenmk@example.com"}
              </div>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="flex size-8 items-center justify-center rounded-full bg-elevated text-subtle"
            aria-label="Close"
          >
            <X size={14} />
          </button>
        </div>

        <div className="space-y-6 p-4">
          <section>
            <p className="text-[10px] font-semibold tracking-widest text-subtle">{t.liveMarket}</p>
            <div className="mt-2 rounded-md border border-line bg-elevated p-3">
              <a
                href="https://www.tradingview.com/symbols/BDXUSD/"
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs font-semibold text-fg hover:text-accent"
              >
                {t.page.tvChartTitle}
              </a>
              <p className="mt-1 text-[10px] text-subtle">
                {t.page.liveFromTv}
              </p>
            </div>
          </section>

          <NavGroup
            title={t.mainMenu}
            onClose={onClose}
            items={[{ to: "/app", icon: Home, label: t.dashboard }]}
          />
          <NavGroup
            title={t.finance}
            onClose={onClose}
            items={[
              { to: "/app/deposit", icon: ArrowDownToLine, label: t.deposit },
              { to: "/app/withdraw", icon: ArrowUpFromLine, label: t.withdraw },
              { to: "/app/history", icon: History, label: t.transactions },
              { to: "/app/plans", icon: LayoutGrid, label: t.plans },
              { to: "/app/swap", icon: Repeat, label: t.swap },
              { to: "/app/markets", icon: LineChart, label: t.markets },
            ]}
          />
          <NavGroup
            title={t.account}
            onClose={onClose}
            items={[
              { to: "/app/profile", icon: Shield, label: t.profile },
              { to: "/app/notifications", icon: Bell, label: t.notifications },
              { to: "/app/referrals", icon: Users, label: t.referrals },
              { to: "/app/settings", icon: Settings, label: t.settings },
              { to: "/app/support", icon: LifeBuoy, label: t.support },
            ]}
          />

          <div className="rounded-lg border border-line bg-elevated p-4">
            <div className="text-[13px] font-semibold text-fg">{t.ready}</div>
            <p className="mt-1 text-[11px] text-subtle">{t.readyBody}</p>
            <Link to="/app/deposit" onClick={onClose}>
              <Button className="mt-3 w-full" size="sm">
                {t.startInvesting}
              </Button>
            </Link>
          </div>

          <button
            type="button"
            onClick={() => {
              void (async () => {
                await signOutCloud();
                logout();
                onClose();
                void navigate({ to: "/login" });
              })();
            }}
            className="flex w-full items-center gap-3 px-3 py-2.5 text-[13px] text-danger"
          >
            <LogOut size={16} /> {t.logout}
          </button>

          <div className="border-t border-line pt-4">
            <BrandLockup to="/app" />
            <p className="mt-3 text-[10px] text-faint">
              {t.page.demoFoot}
            </p>
          </div>
        </div>
      </aside>
    </div>
  );
}

function NavGroup({
  title,
  items,
  onClose,
}: {
  title: string;
  onClose: () => void;
  items: { to: string; icon: ComponentType<{ size?: number }>; label: string }[];
}) {
  return (
    <section>
      <p className="text-[10px] font-semibold tracking-widest text-subtle">{title}</p>
      <div className="mt-2 space-y-1">
        {items.map((item) => (
          <Link
            key={item.to}
            to={item.to}
            onClick={onClose}
            className="flex w-full items-center gap-3 rounded-[10px] px-3 py-2.5 text-[13px] text-muted hover:bg-elevated hover:text-fg"
          >
            <item.icon size={16} /> {item.label}
          </Link>
        ))}
      </div>
    </section>
  );
}
