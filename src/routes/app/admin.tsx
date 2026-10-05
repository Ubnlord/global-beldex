import { createFileRoute, Navigate } from "@tanstack/react-router";

export const Route = createFileRoute("/app/admin")({
  component: LegacyAdminRedirect,
});

function LegacyAdminRedirect() {
  return <Navigate to="/admin" replace />;
}
