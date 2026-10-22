import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/app/swap")({ component: RetiredSwapPage });

function RetiredSwapPage() {
  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-8">
      <section className="rounded-xl border border-line bg-elevated p-5">
        <h2 className="text-xl font-bold text-fg">Currency swaps are retired</h2>
        <p className="mt-2 text-sm leading-6 text-subtle">
          Active account balances and new transactions use BDX only. Historical transaction records are archived and are not converted by this page.
        </p>
      </section>
    </div>
  );
}
