import { Link, createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { Award, ChevronLeft, ChevronRight, ExternalLink, Shield, Zap } from "lucide-react";
import { GuestShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { BeldexLivePrice, LiveBadge } from "@/components/market/live-price";
import { HomeBeldexStats } from "@/components/market/home-stats";
import {
  MiniChart,
  SymbolOverview,
  TickerTape,
} from "@/components/market/tradingview";
import { PlanGrid, TvCredit } from "@/components/platform/plan-card";
import { toast } from "@/components/layout/toast";
import { usePlatform } from "@/lib/platform/store";
import { copy } from "@/lib/platform/i18n";

export const Route = createFileRoute("/")({ component: LandingPage });

function LandingPage() {
  return (
    <GuestShell>
      <Landing />
    </GuestShell>
  );
}

function Landing() {
  const navigate = useNavigate();
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const cards = t.page.companyCards;
  const [company, setCompany] = useState(0);
  const [testimonial, setTestimonial] = useState(0);
  const card = cards[company] ?? cards[0];

  // Testimonial photos are stored as individual assets so each photo keeps its original aspect ratio.
  const testimonials = [
    { name: "ROBERT HOPKINS", body: "I have been a client of Global Beldex for over the last year. I have found this company to be competent, capable, knowledgeable, and a vital component of building my Manufacturing business. I would highly recommend Global Beldex.", image: "/testimonials/robert-hopkins.jpg" },
    { name: "GARY JAMES", body: "I must say this platform is indeed amazing. it was a glimpse at first but today i can account for a real trade when it comes to Investing on Global Beldex.", image: "/testimonials/gary-james.jpg" },
    { name: "KEVIN GAINES", body: "Global Beldex exceeds expectations time after time. Their vast experience and knowledge of the global futures markets will save you time and money when it comes to execution, rolls and research. The entire staff/Traders put a great deal of effort into their relationship with clients, and I am truly appreciative of all they have done for me.", image: "/testimonials/kevin-gaines.jpg" },
    { name: "STEVEN TACCONI", body: "As a satisfied client, I am just writing to tell of how much I have appreciated and enjoyed working with Global Beldex. I would personally rank Global Beldex at the top of the list when it comes to professionalism and overall knowledge of the futures business. Clearly, Global Beldex is interested in the continuing success of their clients. Their attention to personal service is outstanding. It is truly been a positive experience working with them.", image: "/testimonials/steven-tacconi.jpg" },
    { name: "TED & SHANNON", body: "I absolutely love your service. I don’t know how you do it, but I am very, very happy that I found you, and I can’t thank you enough for helping me to realize my dream of achieving a supplemental income to my Administrative business, which I have been able to skyrocket to another level with the extra money I make by Investing with Global Beldex.", image: "/testimonials/ted-shannon.jpg" },
  ];
  const activeTestimonial = testimonials[testimonial] ?? testimonials[0];
  const stepCompany = (dir: number) => {
    if (!cards.length) return;
    setCompany((i) => (i + dir + cards.length) % cards.length);
  };

  return (
    <div className="mx-auto max-w-[1200px] px-4 pb-20 sm:px-6">
      <div className="mt-3">
        <TickerTape />
      </div>

      <div className="mt-8 grid items-start gap-8 sm:mt-12 md:grid-cols-2">
        <div className="rise">
          <LiveBadge className="mb-4" />
          <h1 className="text-balance text-[28px] font-extrabold leading-[1.05] tracking-tight sm:text-[52px] sm:leading-[0.95]">
            {t.page.heroTitle}
            <br />
            <span className="text-subtle">{t.page.heroSub}</span>
          </h1>
          <p className="mt-4 max-w-[520px] text-sm text-muted">{t.page.heroLead}</p>
          <div className="mt-6 flex flex-col gap-3 min-[420px]:flex-row">
            <Button
              className="w-full min-[420px]:w-auto"
              onClick={() => {
                toast(t.page.openingAccount);
                void navigate({ to: "/register" });
              }}
            >
              {t.page.registerNow}
            </Button>
            <Button
              variant="secondary"
              className="w-full min-[420px]:w-auto"
              onClick={() => {
                toast(t.page.openingLogin);
                void navigate({ to: "/login" });
              }}
            >
              {t.explore}
            </Button>
          </div>
        </div>

        <div className="rounded-xl border border-line bg-surface p-4">
          <div className="mb-3 flex items-center justify-between">
            <div className="text-xs text-muted">{t.page.liveMarketTv}</div>
            <a
              href="https://www.tradingview.com/symbols/BDXUSD/"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1 rounded-full border border-line-strong bg-elevated px-2 py-1 text-[10px] text-accent"
            >
              {t.page.trackBdx} <ExternalLink size={10} />
            </a>
          </div>
          <HomeBeldexStats />
          <div className="mt-3">
            <BeldexLivePrice className="mb-3" />
          </div>
          <MiniChart />
          <div className="mt-3 rounded-md border border-line bg-elevated p-3">
            <div className="mb-1 text-[11px] text-muted">{t.page.featured}</div>
            <a
              href="https://www.tradingview.com/symbols/BDXUSD/"
              target="_blank"
              rel="noopener noreferrer"
              className="text-[13px] font-semibold text-fg transition-colors hover:text-accent"
            >
              {t.page.tvChartTitle}
            </a>
            <div className="mt-1 text-[11px] text-subtle">
              {t.page.liveFromTv}
            </div>
          </div>
        </div>
      </div>

      <div className="mt-10 rounded-xl border border-line bg-surface p-4">
        <div className="mb-3 flex items-center justify-between">
          <div className="text-[13px] font-semibold text-fg">{t.page.liveOverview}</div>
          <div className="text-[10px] text-subtle">{t.page.poweredBy}</div>
        </div>
        <SymbolOverview />
        <TvCredit className="mt-2" />
      </div>

      <section className="mt-16">
        <div className="text-center">
          <div className="text-xs font-semibold tracking-widest text-accent">{t.page.conditionsCharges}</div>
        </div>
        <div className="mt-6 text-center">
          <Button
            onClick={() => {
              toast(t.page.openingAccount);
              void navigate({ to: "/register" });
            }}
          >
            {t.page.registerNow}
          </Button>
        </div>
      </section>

      <section className="mt-16">
        <div className="text-center">
          <div className="text-xs font-semibold tracking-widest text-accent">
            {t.page.conditions}
          </div>
          <h2 className="mt-2 text-[28px] font-bold">{t.page.trustTitle}</h2>
          <p className="mx-auto mt-3 max-w-[680px] text-sm text-muted">{t.page.platformsLead}</p>
        </div>
        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          {[
            {
              icon: Shield,
              title: t.page.safeTitle,
              desc: t.page.safeBody,
            },
            {
              icon: Zap,
              title: t.page.execTitle,
              desc: t.page.execBody,
            },
            {
              icon: Award,
              title: t.page.awardTitle,
              desc: t.page.awardBody,
            },
          ].map((item) => (
            <div key={item.title} className="rounded-lg border border-line bg-elevated p-5">
              <item.icon className="text-accent" size={20} />
              <div className="mt-3 font-semibold text-fg">{item.title}</div>
              <div className="mt-1 text-[13px] text-subtle">{item.desc}</div>
            </div>
          ))}
        </div>
      </section>

      <section className="mt-16">
        <div className="text-center">
          <div className="text-xs font-semibold tracking-widest text-accent">RECOGNITION</div>
          <h2 className="mt-2 text-[28px] font-bold text-fg sm:text-[34px]">Awards &amp; Recognition</h2>
        </div>

        <div className="mt-8 grid gap-8 sm:grid-cols-2">
          {[
            {
              image:
                "/awards/award-1.jpg",
              title: "Best Mobile Trading Platform UAE 2022",
            },
            {
              image:
                "/awards/award-2.jpg",
              title: "Most Trusted Trading Platform Europe 2022",
            },
            {
              image:
                "/awards/award-3.jpg",
              title: "Most Innovative CFD Broker",
            },
            {
              image:
                "/awards/award-4.jpg",
              title: "Best Fixed Spread Broker",
            },
          ].map((award) => (
            <div
              key={award.title}
              className="overflow-hidden rounded-xl border border-line bg-surface p-4 sm:p-5"
            >
              <div className="flex min-h-[210px] items-center justify-center rounded-lg bg-white p-2">
                <img
                  src={award.image}
                  alt={award.title}
                  loading="lazy"
                  className="h-auto max-h-[250px] w-full object-contain"
                />
              </div>
              <h3 className="mt-4 text-center text-[16px] font-semibold leading-6 text-fg">
                {award.title}
              </h3>
            </div>
          ))}
        </div>
      </section>

      <section className="mt-16">
        <div className="text-center">
          <div className="text-xs font-semibold tracking-widest text-accent">CLIENT STORIES</div>
          <h2 className="mt-2 text-center text-[28px] font-bold text-fg sm:text-[34px]">
            You&apos;re In Good Company!
          </h2>
        </div>

        <div className="relative mx-auto mt-8 max-w-[760px]">
          <button
            type="button"
            aria-label="Previous testimonial"
            onClick={() => setTestimonial((i) => (i - 1 + testimonials.length) % testimonials.length)}
            className="absolute left-0 top-1/2 z-10 flex size-10 -translate-y-1/2 items-center justify-center rounded-full border border-line bg-surface text-fg shadow-sm"
          >
            <ChevronLeft size={18} />
          </button>
          <button
            type="button"
            aria-label="Next testimonial"
            onClick={() => setTestimonial((i) => (i + 1) % testimonials.length)}
            className="absolute right-0 top-1/2 z-10 flex size-10 -translate-y-1/2 items-center justify-center rounded-full border border-line bg-surface text-fg shadow-sm"
          >
            <ChevronRight size={18} />
          </button>

          <div className="mx-8 overflow-hidden rounded-xl border border-line bg-surface p-6 shadow-sm sm:mx-12 sm:p-10">
            <img
              src={activeTestimonial.image}
              alt={activeTestimonial.name + " testimonial"}
              className="mx-auto max-h-[230px] w-auto max-w-[280px] rounded-xl object-contain"
            />
            <blockquote className="mx-auto mt-7 max-w-[620px] text-center text-[15px] leading-7 text-muted sm:text-[17px] sm:leading-8">
              “{activeTestimonial.body}”
            </blockquote>
            <div className="mt-7 text-center text-sm font-semibold italic tracking-wide text-subtle">
              {activeTestimonial.name}
            </div>
          </div>

          <div className="mt-5 flex justify-center gap-2">
            {testimonials.map((item, i) => (
              <button
                key={item.name}
                type="button"
                aria-label={"Show testimonial from " + item.name}
                onClick={() => setTestimonial(i)}
                className={i === testimonial ? "size-2.5 rounded-full bg-accent" : "size-2.5 rounded-full bg-line-strong"}
              />
            ))}
          </div>
        </div>
      </section>

      <section className="mt-16">
        <div className="text-center">
          <div className="text-xs font-semibold tracking-widest text-accent">{t.how}</div>
          <h2 className="mt-2 text-[28px] font-bold">{t.howTitle}</h2>
        </div>
        <div className="mt-8 grid gap-4 md:grid-cols-3">
          {[
            { n: "01", t: t.page.step1t, d: t.page.step1d },
            { n: "02", t: t.page.step2t, d: t.page.step2d },
            { n: "03", t: t.page.step3t, d: t.page.step3d },
          ].map((s) => (
            <div key={s.n} className="rounded-lg border border-line bg-surface p-5">
              <div className="text-xs font-bold tracking-widest text-accent">{s.n}</div>
              <div className="mt-2 font-semibold">{s.t}</div>
              <p className="mt-1 text-[13px] text-subtle">{s.d}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mt-16">
        <h2 className="text-2xl font-bold">{t.plansTitle}</h2>
        <PlanGrid
          cta={t.openToInvest}
          onAction={() => {
            toast(t.page.openingAccount);
            void navigate({ to: "/register" });
          }}
        />
      </section>

      <section className="mt-16">
        <h2 className="text-2xl font-bold">{t.questions}</h2>
        <div className="mt-6 divide-y divide-line overflow-hidden rounded-lg border border-line bg-surface">
          {t.page.faqs.map((item) => (
            <details key={item.q} className="group p-4">
              <summary className="cursor-pointer list-none text-sm font-semibold text-fg">
                {item.q}
              </summary>
              <p className="mt-2 text-[13px] text-subtle">{item.a}</p>
            </details>
          ))}
        </div>
      </section>

      <section id="global-beldex-difference" className="mt-20 border-t border-line pt-14">
        <div className="mx-auto max-w-[980px]">
          <div className="text-center">
            <div className="text-xs font-semibold tracking-widest text-accent">GLOBAL BELDEX</div>
            <h2 className="mt-2 text-[28px] font-bold text-fg sm:text-[34px]">
              What Makes Global Beldex Limited Different?
            </h2>
            <p className="mx-auto mt-3 max-w-[700px] text-sm leading-6 text-muted">
              Built around transparent market access, useful education, and tools designed to help
              traders make informed decisions.
            </p>
          </div>

          <div className="mt-10 grid gap-4 md:grid-cols-2">
            {[
              {
                title: "We Want You to Succeed",
                body:
                  "Access educational resources, market information, and practical tools designed to help you understand the markets and make more informed decisions.",
              },
              {
                title: "We Believe in Endless Opportunities",
                body:
                  "Explore available markets and instruments from one place, with a mobile-friendly experience built for convenient access wherever you are.",
              },
              {
                title: "Great Investing Conditions",
                body:
                  "We focus on a clear trading experience, responsive interfaces, and reliable access to the tools and market information available on the platform.",
              },
              {
                title: "We Believe You Deserve the Best",
                body:
                  "Use the platform's portfolio, market, investment, and risk-information features to stay organised and make decisions based on your own goals and risk tolerance.",
              },
              {
                title: "We Love to Stay in Touch",
                body:
                  "Keep up with Global Beldex announcements, market updates, platform improvements, and other important information published through our official channels.",
              },
            ].map((item) => (
              <div key={item.title} className="rounded-xl border border-line bg-surface p-5">
                <h3 className="text-[15px] font-semibold text-fg">{item.title}</h3>
                <p className="mt-2 text-[13px] leading-6 text-subtle">{item.body}</p>
              </div>
            ))}
          </div>

          <footer className="mt-12 border-t border-line pt-8">
            <div className="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <div className="text-xs font-semibold tracking-widest text-accent">MARKETS</div>
                <div className="mt-3 grid gap-2 text-[13px]">
                  <Link to="/app/markets" hash="forex" className="text-subtle hover:text-accent">Forex</Link>
                  <Link to="/app/markets" hash="cryptos" className="text-subtle hover:text-accent">Cryptos</Link>
                </div>
              </div>

              <div>
                <div className="text-xs font-semibold tracking-widest text-accent">INVESTMENT</div>
                <div className="mt-3 grid gap-2 text-[13px]">
                  <Link to="/app/plans" className="text-subtle hover:text-accent">Pricing</Link>
                  <Link to="/app/support" hash="faq" className="text-subtle hover:text-accent">Help Centre / FAQ</Link>
                </div>
              </div>

              <div>
                <div className="text-xs font-semibold tracking-widest text-accent">COMPANY</div>
                <div className="mt-3 grid gap-2 text-[13px]">
                  <Link to="/" hash="global-beldex-difference" className="text-subtle hover:text-accent">Why us</Link>
                  <Link to="/app/support" className="text-subtle hover:text-accent">Support</Link>
                </div>
              </div>

              <div>
                <div className="text-xs font-semibold tracking-widest text-accent">ACCOUNT</div>
                <div className="mt-3 grid gap-2 text-[13px]">
                  <Link to="/login" className="text-subtle hover:text-accent">Login</Link>
                  <Link to="/register" className="text-subtle hover:text-accent">Sign Up</Link>
                </div>
              </div>
            </div>

            <section className="mt-8 border-t border-line pt-6" aria-labelledby="contact-address-title">
              <div id="contact-address-title" className="text-xs font-semibold tracking-widest text-accent">
                CONTACT &amp; ADDRESS
              </div>
              <div className="mt-4 grid gap-4 sm:grid-cols-2">
                <div className="rounded-lg border border-line bg-surface p-4">
                  <div className="grid gap-3 text-[13px]">
                    <a
                      href="tel:+14195080286"
                      className="text-subtle transition-colors hover:text-accent"
                    >
                      📞 Call Support <span className="text-fg">+1 (419) 508-0286</span>
                    </a>
                    <a
                      href="https://wa.me/14195080286?text=Hello%20GLOBAL%20BELDEX%20Support%2C%20I%20need%20assistance."
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-subtle transition-colors hover:text-accent"
                    >
                      💬 WhatsApp Support <span className="text-fg">+1 (419) 508-0286</span>
                    </a>
                    <a
                      href="mailto:support@global-beldex.com"
                      className="text-subtle transition-colors hover:text-accent"
                    >
                      📧 Email Support <span className="text-fg">support@global-beldex.com</span>
                    </a>
                  </div>
                </div>

                <a
                  href="https://www.google.com/maps/search/?api=1&query=Lisbeth%20Geoghan%2C%2011481%20West%20County%20Road%20200%20South%2C%20Bloomington%2C%20IN%2047406%2C%20United%20States"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="rounded-lg border border-line bg-surface p-4 text-[13px] text-subtle transition-colors hover:border-accent hover:text-fg"
                >
                  <div className="font-semibold text-fg">📍 Address</div>
                  <div className="mt-2 leading-6">
                    Lisbeth Geoghan
                    <br />
                    11481 West County Road 200 South
                    <br />
                    Bloomington, IN 47406
                    <br />
                    United States
                  </div>
                </a>
              </div>
            </section>

            <div className="mt-8 border-t border-line pt-6">
              <div className="text-xs font-semibold tracking-widest text-accent">LEGAL</div>
              <div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-[13px]">
                <Link to="/legal" hash="privacy" className="text-subtle hover:text-accent">Privacy Policy</Link>
                <Link to="/legal" hash="terms" className="text-subtle hover:text-accent">Terms of Service</Link>
                <Link to="/legal" hash="risk" className="text-subtle hover:text-accent">Risk Disclosure</Link>
              </div>
            </div>

            <div className="mt-8 space-y-3 text-[11px] leading-5 text-faint">
              <p>
                This website may be accessed worldwide. Information and services available through
                the platform may vary by jurisdiction and eligibility. Please review the applicable
                terms, disclosures, and legal information before using any trading or investment
                service.
              </p>
              <p>
                Forex, CFDs, and other leveraged products can result in significant losses and may
                not be suitable for every client. Prices can move rapidly against you and you may
                lose some or all of the funds committed. Make sure you understand the risks and
                consider seeking independent financial advice where appropriate.
              </p>
              <p className="pt-2 text-center">
                Copyright © 2025. All Rights Reserved
              </p>
            </div>
          </footer>
        </div>
      </section>

    </div>
  );
}
