import { createFileRoute } from "@tanstack/react-router";
import { Bell } from "lucide-react";
import { useEffect } from "react";
import { usePlatform } from "@/lib/platform/store";
import { copy } from "@/lib/platform/i18n";

export const Route = createFileRoute("/app/notifications")({
  component: NotificationsPage,
});

function NotificationsPage() {
  const notices = usePlatform((s) => s.notices);
  const mark = usePlatform((s) => s.markNoticesRead);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];

  useEffect(() => {
    mark();
  }, [mark]);

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="text-xl font-bold">{t.notifications}</h2>
      <div className="mt-6">
        {notices.length === 0 ? (
          <div className="rounded-lg border border-line bg-elevated p-10 text-center">
            <div className="mx-auto flex size-14 items-center justify-center rounded-full bg-surface text-subtle">
              <Bell size={22} />
            </div>
            <div className="mt-4 font-semibold">{t.noNotes}</div>
            <p className="mt-1 text-xs text-subtle">{t.noNotesBody}</p>
          </div>
        ) : (
          <div className="divide-y divide-line overflow-hidden rounded-lg border border-line bg-elevated">
            {notices.map((n) => (
              <div key={n.id} className="p-4">
                <div className="text-[13px] font-semibold text-fg">{n.title}</div>
                <div className="mt-1 text-[12px] text-subtle">{n.body}</div>
                <div className="mt-2 text-[10px] text-faint">
                  {new Date(n.time).toLocaleString()}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
