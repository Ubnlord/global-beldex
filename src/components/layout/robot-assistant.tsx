import { Bot, ChevronDown, Maximize2, MessageCircle, Send, X } from "lucide-react";
import { useMemo, useState } from "react";
import { usePlatform } from "@/lib/platform/store";

type ChatMessage = {
  id: number;
  from: "bot" | "user";
  text: string;
};

const QUICK_REPLIES = [
  "How do I deposit?",
  "How do withdrawals work?",
  "Tell me about Plans",
  "How is daily interest calculated?",
];

function getReply(message: string) {
  const q = message.toLowerCase();

  if (q.includes("deposit")) {
    return "To deposit, open Deposit from the bottom menu, choose an asset, enter the amount, and submit the request. Deposits are reviewed before your balance is credited.";
  }
  if (q.includes("withdraw")) {
    return "To withdraw, open Withdraw, select your asset, enter the amount and destination address, then submit. Withdrawal requests are reviewed before processing.";
  }
  if (q.includes("plan") || q.includes("invest")) {
    return "Open Plans to view the available investment plans. Active plans show Today's Interest, Total Interest Earned, Next Interest, and Days Remaining.";
  }
  if (q.includes("interest") || q.includes("daily")) {
    return "Daily interest is calculated from the active plan's principal and daily rate. The server records accruals, and the Plans screen displays the credited total.";
  }
  if (q.includes("support") || q.includes("help") || q.includes("contact")) {
    return "For account-specific help, open Menu → Support and send us a message. Please never share your password, verification code, or private keys.";
  }
  if (q.includes("hello") || q.includes("hi") || q.includes("hey")) {
    return "Hello! 👋 I'm the Global Beldex Assistant. Ask me about deposits, withdrawals, plans, daily interest, or support.";
  }

  return "I can help with deposits, withdrawals, investment plans, daily interest, and support. Choose a question below or type your own.";
}

export function RobotAssistant() {
  const lang = usePlatform((s) => s.lang);
  const user = usePlatform((s) => s.user);
  const [open, setOpen] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [input, setInput] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>(() => [
    {
      id: 1,
      from: "bot",
      text: user?.username
        ? `Welcome back, ${user.username}! 👋 How can I assist you today?`
        : "Welcome to GLOBAL BELDEX! 👋 How can I assist you today?",
    },
  ]);

  const statusText = useMemo(() => (lang === "en" ? "We reply immediately" : "We are here to help"), [lang]);

  const send = (text = input) => {
    const value = text.trim();
    if (!value) return;

    setMessages((current) => [
      ...current,
      { id: Date.now(), from: "user", text: value },
      { id: Date.now() + 1, from: "bot", text: getReply(value) },
    ]);
    setInput("");
  };

  return (
    <>
      {!open && (
        <button
          type="button"
          onClick={() => setOpen(true)}
          aria-label="Open Global Beldex Assistant"
          className="fixed bottom-[88px] right-4 z-[70] flex size-14 items-center justify-center rounded-full border border-accent/40 bg-accent text-accent-fg shadow-2xl shadow-black/30 transition hover:scale-105 active:scale-95"
        >
          <span className="relative">
            <Bot size={28} strokeWidth={2.2} />
            <span className="absolute -right-1 -top-1 size-2.5 rounded-full bg-white" />
          </span>
        </button>
      )}

      {open && (
        <div
          className={
            expanded
              ? "fixed inset-3 z-[80] flex flex-col overflow-hidden rounded-2xl border border-line bg-bg shadow-2xl"
              : "fixed bottom-4 right-3 z-[80] flex h-[min(650px,calc(100dvh-110px))] w-[min(380px,calc(100vw-24px))] flex-col overflow-hidden rounded-2xl border border-line bg-bg shadow-2xl"
          }
        >
          <div className="flex items-center justify-between bg-accent px-4 py-3 text-accent-fg">
            <div className="flex min-w-0 items-center gap-3">
              <div className="flex size-10 shrink-0 items-center justify-center rounded-full bg-white/15">
                <Bot size={23} />
              </div>
              <div className="min-w-0">
                <div className="truncate text-sm font-bold">GLOBAL BELDEX Assistant</div>
                <div className="flex items-center gap-1.5 text-[10px] opacity-90">
                  <span className="size-1.5 rounded-full bg-white" />
                  {statusText}
                </div>
              </div>
            </div>
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={() => setExpanded((value) => !value)}
                aria-label={expanded ? "Minimize assistant" : "Expand assistant"}
                className="rounded-full p-2 hover:bg-white/10"
              >
                {expanded ? <ChevronDown size={18} /> : <Maximize2 size={17} />}
              </button>
              <button
                type="button"
                onClick={() => setOpen(false)}
                aria-label="Close assistant"
                className="rounded-full p-2 hover:bg-white/10"
              >
                <X size={18} />
              </button>
            </div>
          </div>

          <div className="flex-1 space-y-3 overflow-y-auto bg-surface/50 p-4">
            {messages.map((message) => (
              <div
                key={message.id}
                className={message.from === "user" ? "ml-auto max-w-[82%]" : "mr-auto max-w-[88%]"}
              >
                <div
                  className={
                    message.from === "user"
                      ? "rounded-2xl rounded-br-md bg-accent px-3.5 py-2.5 text-sm text-accent-fg"
                      : "rounded-2xl rounded-bl-md border border-line bg-elevated px-3.5 py-2.5 text-sm text-fg"
                  }
                >
                  {message.text}
                </div>
              </div>
            ))}

            {messages.length === 1 && (
              <div className="space-y-2 pt-1">
                {QUICK_REPLIES.map((reply) => (
                  <button
                    key={reply}
                    type="button"
                    onClick={() => send(reply)}
                    className="block w-full rounded-xl border border-line bg-elevated px-3 py-2 text-left text-xs text-fg transition hover:border-accent/60"
                  >
                    {reply}
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="border-t border-line bg-elevated p-3">
            <div className="flex items-center gap-2 rounded-xl border border-line bg-surface px-3 py-1.5">
              <MessageCircle size={17} className="shrink-0 text-muted" />
              <input
                value={input}
                onChange={(event) => setInput(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") send();
                }}
                placeholder="Type your message here"
                aria-label="Message Global Beldex Assistant"
                className="min-w-0 flex-1 bg-transparent py-2 text-sm text-fg outline-none placeholder:text-muted"
              />
              <button
                type="button"
                onClick={() => send()}
                aria-label="Send message"
                disabled={!input.trim()}
                className="flex size-9 items-center justify-center rounded-full bg-accent text-accent-fg disabled:opacity-40"
              >
                <Send size={16} />
              </button>
            </div>
            <div className="mt-2 text-center text-[9px] text-muted">
              Automated assistant · Never share passwords or private keys
            </div>
          </div>
        </div>
      )}
    </>
  );
}
