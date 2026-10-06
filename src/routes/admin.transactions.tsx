import { createFileRoute } from "@tanstack/react-router";
import { AdminPage } from "@/routes/admin";

export const Route = createFileRoute("/admin/transactions")({
  component: TransactionsAdminPage,
});

function TransactionsAdminPage() {
  return <AdminPage initialTab="transactions" />;
}
