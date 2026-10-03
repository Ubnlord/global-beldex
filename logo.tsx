import { Link } from "@tanstack/react-router";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { cn } from "@/lib/utils";

export function Mark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      className={cn("size-8 shrink-0", className)}
      aria-hidden
    >
      <rect width="32" height="32" rx="8" fill="#0A0A18" />
      <rect x="0.8" y="0.8" width="30.4" height="30.4" rx="7.4" fill="none" stroke="#2AF5D4" strokeWidth="1.2" />
      <circle cx="16" cy="16" r="8.2" fill="none" stroke="#2AF5D4" strokeWidth="1.5" />
      <ellipse cx="16" cy="16" rx="3.5" ry="8.2" fill="none" stroke="#2AF5D4" strokeWidth="1.3" />
      <path d="M7.8 16h16.4" stroke="#2AF5D4" strokeWidth="1.3" />
      <path d="M9 12.4c2.1.8 4.4 1.2 7 1.2s4.9-.4 7-1.2" fill="none" stroke="#2AF5D4" strokeWidth="1.15" />
      <path d="M9 19.6c2.1-.8 4.4-1.2 7-1.2s4.9.4 7 1.2" fill="none" stroke="#2AF5D4" strokeWidth="1.15" />
    </svg>
  );
}

export function BrandLockup({
  to = "/",
  subtitle,
}: {
  to?: string;
  subtitle?: string;
}) {
  const lang = usePlatform((s) => s.lang);
  return (
    <Link to={to} className="flex min-w-0 items-center gap-2">
      <Mark />
      <div className="min-w-0">
        <div className="truncate text-sm font-bold leading-none tracking-tight text-fg">
          GLOBAL BELDEX
        </div>
        <div className="mt-0.5 hidden text-[10px] leading-none text-subtle sm:block">
          {subtitle ?? copy[lang].tag}
        </div>
      </div>
    </Link>
  );
}