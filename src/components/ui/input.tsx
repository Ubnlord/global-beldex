import type { InputHTMLAttributes, ReactNode } from "react";
import { cn } from "@/lib/utils";

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "mt-1 w-full rounded-md border border-line-strong bg-elevated px-4 py-3 text-base text-fg outline-none placeholder:text-subtle focus:border-accent",
        className,
      )}
      {...props}
    />
  );
}

export function FieldLabel({ children }: { children: ReactNode }) {
  return <label className="text-[11px] text-muted">{children}</label>;
}
