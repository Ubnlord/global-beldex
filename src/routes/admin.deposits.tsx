import { createFileRoute } from "@tanstack/react-router";
import { AdminPage } from "@/routes/admin";

export const Route = createFileRoute("/admin/deposits")({
  component: DepositsAdminPage,
});

function DepositsAdminPage() {
  return <AdminPage initialTab="transactions" transactionType="deposit" />;
}
