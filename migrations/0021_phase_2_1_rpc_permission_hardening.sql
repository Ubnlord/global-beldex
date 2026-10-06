-- Phase 2.1: tighten exposed SECURITY DEFINER RPC permissions.
-- admin_financial_reconciliation is read-only operational tooling and is not
-- called by the browser admin UI. Keep it out of the authenticated REST RPC surface.
revoke execute on function public.admin_financial_reconciliation() from public;
revoke execute on function public.admin_financial_reconciliation() from anon;
revoke execute on function public.admin_financial_reconciliation() from authenticated;
grant execute on function public.admin_financial_reconciliation() to service_role;
