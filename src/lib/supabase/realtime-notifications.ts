import { useEffect } from "react";
import { supabase } from "@/lib/supabase/client";
import { usePlatform } from "@/lib/platform/store";

let audioContext: AudioContext | null = null;

export function playNotificationSound() {
  try {
    const AudioCtx =
      window.AudioContext ||
      (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioCtx) return;

    audioContext ??= new AudioCtx();
    if (audioContext.state === "suspended") void audioContext.resume();

    const now = audioContext.currentTime;
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();

    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(880, now);
    oscillator.frequency.setValueAtTime(1175, now + 0.08);

    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(0.12, now + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.22);

    oscillator.connect(gain);
    gain.connect(audioContext.destination);
    oscillator.start(now);
    oscillator.stop(now + 0.24);
  } catch {
    // Browser autoplay/audio restrictions should never break the app.
  }
}

export async function requestRealtimeNotificationPermission() {
  if (typeof Notification === "undefined") return "unsupported" as const;
  if (Notification.permission === "default") {
    return await Notification.requestPermission();
  }
  return Notification.permission;
}

export function showRealtimeNotification(title: string, body: string) {
  if (typeof Notification === "undefined" || Notification.permission !== "granted") return;
  try {
    new Notification(title, { body, icon: "/favicon.ico", tag: "global-beldex-realtime" });
  } catch {
    // Notifications may be blocked by the browser or installed PWA context.
  }
}

function describeTransaction(record: Record<string, unknown>) {
  const type = String(record.type ?? "transaction");
  const amount = Number(record.amount ?? 0);
  const status = String(record.status ?? "updated");
  const label =
    type === "deposit" ? "Deposit" :
    type === "withdraw" ? "Withdrawal" :
    type === "bonus" ? "Balance credit" :
    type === "plan" ? "Investment plan" :
    type === "swap" ? "Swap" :
    "Transaction";

  const amountText = Number.isFinite(amount) && amount > 0
    ? " · $" + amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    : "";

  return {
    title: label + " update",
    body: label + amountText + " is now " + status + ".",
  };
}

export function useRealtimeUserNotifications() {
  const user = usePlatform((s) => s.user);
  const soundEnabled = usePlatform((s) => s.notificationSound);
  const addNotice = usePlatform((s) => s.addNotice);
  const refreshTransactions = usePlatform((s) => s.refreshTransactions);

  useEffect(() => {
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let cancelled = false;

    void (async () => {
      const { data: { user: authUser } } = await supabase.auth.getUser();
      if (cancelled || !authUser) return;

      channel = supabase
        .channel("user-transaction-notifications-" + authUser.id)
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "transaction",
            filter: "user_id=eq." + authUser.id,
          },
          (payload) => {
            const record = (payload.new ?? payload.old ?? {}) as Record<string, unknown>;
            const { title, body } = describeTransaction(record);
            addNotice(title, body);
            void refreshTransactions();
            if (soundEnabled) playNotificationSound();
            showRealtimeNotification(title, body);
          },
        )
        .subscribe();
    })();

    return () => {
      cancelled = true;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [addNotice, refreshTransactions, soundEnabled, user?.username]);
}
