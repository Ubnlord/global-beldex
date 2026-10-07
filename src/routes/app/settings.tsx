import { createFileRoute, Link } from "@tanstack/react-router";
import { type ReactNode } from "react";
import { Bell, BellRing, Volume2, VolumeX } from "lucide-react";
import { toast } from "@/components/layout/toast";
import { Avatar } from "@/components/layout/avatar";
import { Button } from "@/components/ui/button";
import { copy, LANGS, type Lang } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { playNotificationSound, requestRealtimeNotificationPermission } from "@/lib/supabase/realtime-notifications";

export const Route = createFileRoute("/app/settings")({ component: SettingsPage });

function SettingsPage() {
  const lang = usePlatform((s) => s.lang);
  const setLang = usePlatform((s) => s.setLang);
  const user = usePlatform((s) => s.user);
  const notificationSound = usePlatform((s) => s.notificationSound);
  const setNotificationSound = usePlatform((s) => s.setNotificationSound);
  const t = copy[lang];

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="text-xl font-bold">{t.settings}</h2>
      <p className="mt-1 text-xs text-subtle">{t.settingsLead}</p>

      <section className="mt-6">
        <div className="text-[11px] font-semibold tracking-widest text-subtle">{t.account}</div>
        <div className="mt-2 rounded-lg border border-line bg-elevated p-4">
          <div className="flex items-center gap-3">
            <Avatar name={user?.name} src={user?.avatar} className="size-12 text-sm" />
            <div className="min-w-0">
              <div className="truncate font-semibold">{user?.name || "—"}</div>
              <div className="truncate text-xs text-subtle">{user?.email}</div>
            </div>
          </div>
          <Link to="/app/profile" className="mt-4 block">
            <Button variant="secondary" className="w-full" size="sm">
              {t.openProfile}
            </Button>
          </Link>
        </div>
      </section>

      <section className="mt-6">
        <div className="text-[11px] font-semibold tracking-widest text-subtle">{t.preferences}</div>
        <div className="mt-2">
          <Row label={t.settingsLang}>
            <select
              value={lang}
              onChange={(e) => {
                const next = e.target.value as Lang;
                setLang(next);
                toast(LANGS.find((item) => item.id === next)?.label ?? next);
              }}
              className="h-11 w-full rounded-md border border-line-strong bg-surface px-3 text-base text-fg outline-none sm:w-auto"
            >
              {LANGS.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.label}
                </option>
              ))}
            </select>
          </Row>
        </div>
      </section>

      <section className="mt-6">
        <div className="text-[11px] font-semibold tracking-widest text-subtle">Notifications</div>
        <div className="mt-2 space-y-3">
          <Row label="Real-time alerts">
            <div className="flex items-center gap-2 text-xs text-subtle">
              <Bell size={16} className="text-accent" />
              <span>Live account updates</span>
            </div>
          </Row>
          <Row label="Notification sound">
            <button
              type="button"
              onClick={() => {
                const next = !notificationSound;
                setNotificationSound(next);
                if (next) playNotificationSound();
              }}
              className="flex items-center gap-2 rounded-full border border-line-strong bg-surface px-3 py-2 text-xs font-semibold text-fg"
              aria-pressed={notificationSound}
            >
              {notificationSound ? <Volume2 size={15} className="text-accent" /> : <VolumeX size={15} />}
              {notificationSound ? "On" : "Off"}
            </button>
          </Row>
          <Row label="Browser notifications">
            <button
              type="button"
              onClick={async () => {
                const permission = await requestRealtimeNotificationPermission();
                if (permission === "granted") toast("Browser notifications enabled");
                else if (permission === "denied") toast("Browser notifications are blocked");
                else toast("Browser notifications are not available here");
              }}
              className="flex items-center gap-2 rounded-full border border-line-strong bg-surface px-3 py-2 text-xs font-semibold text-fg"
            >
              <BellRing size={15} className="text-accent" />
              Enable
            </button>
          </Row>
        </div>
      </section>

      <section className="mt-6">
        <div className="text-[11px] font-semibold tracking-widest text-subtle">{t.security}</div>
        <div className="mt-2 space-y-3">
          <Row label={t.session}>
            <span className="text-xs text-subtle">{t.sessionBody}</span>
          </Row>
          <Row label={t.marketData}>
            <span className="text-xs text-muted">TradingView · CRYPTO:BDXUSD</span>
          </Row>
        </div>
      </section>
    </div>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-line bg-elevated px-4 py-4 sm:flex-row sm:items-center sm:justify-between">
      <div className="text-sm text-fg">{label}</div>
      {children}
    </div>
  );
}
