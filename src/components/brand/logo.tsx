import { Link } from "@tanstack/react-router";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { cn } from "@/lib/utils";


export function Mark({ className }: { className?: string }) {
  return (
    <img
      src="/brand-logo.png"
      alt="GLOBAL BELDEX"
      className={cn("size-8 shrink-0 object-contain", className)}
    />
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
