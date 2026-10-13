begin;

create extension if not exists pgtap with schema extensions;
select plan(4);

select ok(
  position('admin_has_permission(''view_transactions'')' in
    pg_get_functiondef('public.admin_financial_reconciliation()'::regprocedure)) > 0,
  'legacy reconciliation requires explicit view_transactions permission'
);

select ok(
  position('admin_has_permission(''view_transactions'')' in
    pg_get_functiondef('public.admin_financial_reconciliation_v2()'::regprocedure)) > 0,
  'currency-aware reconciliation requires explicit view_transactions permission'
);

select ok(
  position('not public.is_admin()' in
    pg_get_functiondef('public.admin_financial_reconciliation()'::regprocedure)) > 0,
  'legacy reconciliation still requires administrator status'
);

select ok(
  position('not public.is_admin()' in
    pg_get_functiondef('public.admin_financial_reconciliation_v2()'::regprocedure)) > 0,
  'currency-aware reconciliation still requires administrator status'
);

select * from finish();
rollback;
