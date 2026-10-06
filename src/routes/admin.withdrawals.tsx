import { createFileRoute } from "@tanstack/react-router";
import { AdminPage } from "@/routes/admin";

export const Route = createFileRoute("/admin/withdrawals")({
  component: WithdrawalsAdminPage,
});

function WithdrawalsAdminPage() {
  return <AdminPage initialTab="transactions" transactionType="withdraw" />;
}
