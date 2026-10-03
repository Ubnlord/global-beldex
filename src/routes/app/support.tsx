import { createFileRoute } from "@tanstack/react-router";
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
    const href = `mailto:globalbeldex1@gmail.com?subject=${encodeURIComponent(subject.trim())}&body=${encodeURIComponent(body.trim())}`;
    window.location.href = href;
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="text-xl font-bold">{t.support}</h2>
      <p className="mt-1 text-xs text-subtle">{t.supportLead}</p>
      <div className="mt-4 rounded-lg border border-line bg-elevated px-4 py-3">
        <div className="text-[11px] text-subtle">{t.supportEmail}</div>
        <a
          href="mailto:globalbeldex1@gmail.com"
          className="mt-0.5 inline-block text-sm font-semibold text-accent underline underline-offset-2"
        >
          globalbeldex1@gmail.com
        </a>
      </div>
      <div className="mt-3 rounded-lg border border-line bg-elevated px-4 py-3">
        <div className="text-[11px] text-subtle">{t.supportPhone}</div>
        <a
          href="tel:+447404603931"
          className="mt-0.5 inline-block text-sm font-semibold text-accent underline underline-offset-2"
        >
          +44 7404 603931
        </a>
      </div>
      <div className="mt-3 rounded-lg border border-line bg-elevated px-4 py-3">
        <div className="text-[11px] text-subtle">{t.supportAddress}</div>
        <a
          href="https://maps.google.com/?q=Bethanee+Dong+Tumulus+Avenue+Newcastle+upon+Tyne+NE6+4US"
          target="_blank"
          rel="noopener noreferrer"
          className="mt-1 block text-sm font-semibold leading-5 text-accent underline underline-offset-2"
        >
          Bethanee Dong
          <br />
          Tumulus Avenue
          <br />
          Newcastle upon Tyne
          <br />
          NE6 4US
          <br />
          United Kingdom
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
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder={t.page.messagePh}
            rows={4}
            className="mt-1 w-full rounded-md border border-line-strong bg-surface px-4 py-3 text-base text-fg outline-none focus:border-accent"
          />
        </div>
        <Button type="submit" className="w-full">
          {t.send}
        </Button>
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
      <div className="mt-6 divide-y divide-line overflow-hidden rounded-lg border border-line bg-elevated">
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