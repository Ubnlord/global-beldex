import { createFileRoute, Link } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { GuestShell } from "@/components/layout/app-shell";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";

export const Route = createFileRoute("/legal")({ component: LegalPage });

function LegalPage() {
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const p = t.page;
  return (
    <GuestShell>
      <article className="mx-auto max-w-[720px] px-4 py-10 sm:px-6">
        <p className="text-xs font-semibold tracking-widest text-accent">GLOBAL BELDEX</p>
        <h1 className="mt-2 text-[28px] font-bold tracking-tight">{p.legalTitle}</h1>
        <p className="mt-3 text-sm text-muted">{p.legalIntro}</p>

        <Section id="terms" title={t.termsWord}>
          {p.legalTerms.map((text) => (
            <p key={text}>{text}</p>
          ))}
        </Section>

        <Section id="privacy" title={t.privacyWord}>
          {p.legalPrivacy.map((text) => (
            <p key={text}>{text}</p>
          ))}
        </Section>

        <Section id="risk" title={t.riskWord}>
          {p.legalRisk.map((text) => (
            <p key={text}>{text}</p>
          ))}
        </Section>

        <p className="mt-10 text-sm">
          <Link to="/" className="text-accent">
            {p.legalBack}
          </Link>
        </p>
      </article>
    </GuestShell>
  );
}

function Section({
  id,
  title,
  children,
}: {
  id: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <section id={id} className="mt-10 scroll-mt-24">
      <h2 className="text-xl font-bold">{title}</h2>
      <div className="mt-3 space-y-3 text-sm leading-relaxed text-muted">{children}</div>
    </section>
  );
}
