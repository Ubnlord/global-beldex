import { Check } from "lucide-react";
import { useEffect, useState } from "react";
import { explain } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";

let pushFn: ((msg: string) => void) | null = null;

export function toast(msg: string) {
  pushFn?.(msg);
}

export function toastError(code: string) {
  toast(explain(usePlatform.getState().lang, code));
}

export function ToastHost() {
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => {
    pushFn = (m) => {
      setMsg(m);
      window.setTimeout(() => setMsg(null), 2600);
    };
    return () => {
      pushFn = null;
    };
  }, []);

  if (!msg) return null;
  return (
    <div className="fixed bottom-[90px] left-1/2 z-[80] flex -translate-x-1/2 items-center gap-2 rounded-full border border-line-strong bg-elevated px-4 py-2.5 text-xs text-fg shadow-xl">
      <div className="flex size-5 items-center justify-center rounded-full bg-accent text-accent-fg">
        <Check size={12} />
      </div>
      {msg}
    </div>
  );
}
