import { createFileRoute } from "@tanstack/react-router";
import { Mail, Phone, MessageCircle } from "lucide-react";
import { useState, type FormEvent } from "react";
import { toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";

export const Route = createFileRoute("/app/support")({ component: SupportPage });

function SupportPage() {
  const tickets = usePlatform((s) => s.tickets);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (!subject.trim() || !body.trim()) {
      toastError("NEED_TICKET");
      return;
    }
    const href = `mailto:support@global-beldex.com?subject=${encodeURIComponent(subject.trim())}&body=${encodeURIComponent(body.trim())}`;
    window.location.href = href;
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="text-xl font-bold">{t.support}</h2>
      <p className="mt-1 text-xs text-subtle">{t.supportLead}</p>

      <div id="contact" className="mt-4 scroll-mt-24 rounded-lg border border-line bg-elevated px-4 py-3">
        <div className="text-[11px] text-subtle">{t.supportEmail}</div>

        <a
          href="mailto:support@global-beldex.com"
          className="mt-2 inline-flex w-full items-center justify-center gap-2 rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-white transition-opacity hover:opacity-90"
        >
          <Mail size={16} />
          Email Support
        </a>

        <a
          href="tel:+14195080286"
          className="mt-2 inline-flex w-full items-center justify-center gap-2 rounded-md border border-line-strong bg-surface px-4 py-2.5 text-sm font-semibold text-fg transition-opacity hover:opacity-90"
        >
          <Phone size={16} />
          Call Support
        </a>

        <a
          href="https://wa.me/14195080286?text=Hello%20GLOBAL%20BELDEX%20Support%2C%20I%20need%20assistance."
          target="_blank"
          rel="noopener noreferrer"
          className="mt-2 inline-flex w-full items-center justify-center gap-2 rounded-md border border-line-strong bg-surface px-4 py-2.5 text-sm font-semibold text-fg transition-opacity hover:opacity-90"
        >
          <MessageCircle size={16} />
          WhatsApp Support
        </a>

        <div className="mt-2 text-center text-xs text-subtle">+1 (419) 508-0286</div>
      </div>

      <div className="mt-3 rounded-lg border border-line bg-elevated px-4 py-3">
        <div className="text-[11px] text-subtle">{t.supportAddress}</div>
        <a
          href="https://maps.google.com/?q=Lisbeth+Geoghan%2C+11481+West+County+Road+200+South%2C+Bloomington%2C+IN+47406%2C+United+States"
          target="_blank"
          rel="noopener noreferrer"
          className="mt-1 block text-sm font-semibold leading-5 text-accent underline underline-offset-2"
        >
          Lisbeth Geoghan
          <br />
          11481 West County Road 200 South
          <br />
          Bloomington, IN 47406
          <br />
          United States
        </a>
      </div>

      <form onSubmit={onSubmit} className="mt-6 space-y-4 rounded-lg border border-line bg-elevated p-5">
        <div className="text-sm font-semibold">{t.messageDesk}</div>
        <div>
          <FieldLabel>{t.subject}</FieldLabel>
          <Input value={subject} onChange={(e) => setSubject(e.target.value)} placeholder={t.page.subjectPh} />
        </div>
        <div>
          <FieldLabel>{t.message}</FieldLabel>
          <textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder={t.page.messagePh} rows={4} className="mt-1 w-full rounded-md border border-line-strong bg-surface px-4 py-3 text-base text-fg outline-none focus:border-accent" />
        </div>
        <Button type="submit" className="w-full">{t.send}</Button>
      </form>

      {(tickets ?? []).length > 0 && (
        <div className="mt-4 divide-y divide-line overflow-hidden rounded-lg border border-line bg-elevated">
          {tickets.map((ticket) => (
            <div key={ticket.id} className="p-4">
              <div className="flex items-center justify-between gap-3">
                <div className="text-[13px] font-semibold">{ticket.subject}</div>
                <div className="text-[10px] uppercase tracking-widest text-accent">{ticket.status}</div>
              </div>
              <p className="mt-1 text-[12px] text-subtle">{ticket.body}</p>
            </div>
          ))}
        </div>
      )}

      <div id="faq" className="mt-6 scroll-mt-24 divide-y divide-line overflow-hidden rounded-lg border border-line bg-elevated">
        {t.page.faqs.map((item) => (
          <details key={item.q} className="p-4">
            <summary className="cursor-pointer text-sm font-semibold">{item.q}</summary>
            <p className="mt-2 text-[13px] text-subtle">{item.a}</p>
          </details>
        ))}
      </div>
    </div>
  );
}
