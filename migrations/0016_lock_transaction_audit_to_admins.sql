begin;

-- Remove the legacy policy that exposed a user's own transaction audit rows.
drop policy if exists transaction_audit_select_own_or_admin on public.transaction_audit;

commit;
