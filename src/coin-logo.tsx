import { cn } from "@/lib/utils";

export type CoinMark = "beldex" | "bitcoin" | "ethereum";

export function coinMark(id: string): CoinMark {
  const key = id.toUpperCase();
  if (key === "BTC" || key === "BITCOIN") return "bitcoin";
  if (key === "ETH" || key === "ETHEREUM") return "ethereum";
  return "beldex";
}

export function CoinLogo({
  coin,
  size = 32,
  className,
}: {
  coin: CoinMark | string;
  size?: number;
  className?: string;
}) {
  const mark = coinMark(coin);
  return (
    <span className={cn("inline-flex shrink-0", className)} style={{ width: size, height: size }}>
      {mark === "bitcoin" ? <Bitcoin size={size} /> : mark === "ethereum" ? <Ethereum size={size} /> : <Beldex size={size} />}
    </span>
  );
}

function Bitcoin({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden>
      <circle cx="16" cy="16" r="16" fill="#F7931A" />
      <path
        fill="#fff"
        d="M23.2 13.9c.3-2-1.2-3.1-3.3-3.8l.7-2.7-1.7-.4-.7 2.6c-.4-.1-.9-.2-1.3-.3l.7-2.7-1.7-.4-.7 2.7c-.3-.1-.7-.2-1-.3l.1-.1-2.3-.6-.4 1.8s1.2.3 1.2.3c.6.2.8.6.7 1l-.8 3.1c0 .1.1.2.2.1l-.2-.1-1.1 4.4c-.1.2-.3.6-.8.4 0 0-1.2-.3-1.2-.3l-.8 1.9 2.2.5c.4.1.8.2 1.2.3l-.7 2.8 1.7.4.7-2.7c.4.1.9.2 1.3.3l-.7 2.7 1.7.4.7-2.8c2.9.5 5 .3 5.9-2.3.7-2.1-.1-3.3-1.6-4.1 1.1-.3 1.9-1 2.2-2.6zm-3.9 5.4c-.5 2-3.9.9-5 .6l.9-3.6c1.1.3 4.6.8 4.1 3zm.5-5.4c-.5 1.8-3.3.9-4.2.7l.8-3.2c.9.2 3.9.7 3.4 2.5z"
      />
    </svg>
  );
}

function Ethereum({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden>
      <circle cx="16" cy="16" r="16" fill="#627EEA" />
      <path fill="#fff" fillOpacity="0.6" d="M16.5 6.5v7.4l6.3 2.8z" />
      <path fill="#fff" d="M16.5 6.5 10.2 16.7l6.3-2.8z" />
      <path fill="#fff" fillOpacity="0.6" d="M16.5 21.6v5.1l6.3-8.8z" />
      <path fill="#fff" d="M16.5 26.7v-5.1l-6.3-3.7z" />
      <path fill="#fff" fillOpacity="0.2" d="m16.5 20.4 6.3-3.7-6.3-2.8z" />
      <path fill="#fff" fillOpacity="0.6" d="m10.2 16.7 6.3 3.7v-6.5z" />
    </svg>
  );
}

function Beldex({ size }: { size: number }) {
  return (
    <img
      src="/coins/beldex.png"
      alt=""
      width={size}
      height={size}
      className="size-full rounded-full object-cover"
    />
  );
}
