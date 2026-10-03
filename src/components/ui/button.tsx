import { cva, type VariantProps } from "class-variance-authority";
import { Slot } from "@radix-ui/react-slot";
import { cn } from "@/lib/utils";
import type { ButtonHTMLAttributes } from "react";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 font-semibold transition-colors duration-150 disabled:opacity-50 disabled:pointer-events-none outline-none focus-visible:ring-2 focus-visible:ring-accent/60",
  {
    variants: {
      variant: {
        primary:
          "bg-accent text-accent-fg hover:bg-accent-hover",
        secondary:
          "bg-elevated border border-line-strong text-fg hover:bg-panel",
        ghost: "text-muted hover:text-fg",
        danger: "bg-danger/15 text-danger hover:bg-danger/25",
        mint: "bg-accent text-accent-fg hover:bg-accent-hover",
      },
      size: {
        sm: "h-9 px-3 text-sm rounded-full",
        md: "h-11 px-5 text-sm rounded-full",
        lg: "h-12 px-6 text-sm rounded-full",
        icon: "size-9 rounded-full",
      },
    },
    defaultVariants: { variant: "primary", size: "md" },
  },
);

export function Button({
  className,
  variant,
  size,
  asChild,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> &
  VariantProps<typeof buttonVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot : "button";
  return (
    <Comp className={cn(buttonVariants({ variant, size }), className)} {...props} />
  );
}
