begin;

create extension if not exists pgtap with schema extensions;
select plan(3);

select ok(
  exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='transaction'
      and t.tgname='audit_admin_bonus_insert'
      and not t.tgisinternal
  ),
  'transaction insert trigger records audit linkage for future admin bonuses'
);

select ok(
  position('admin_bonus_created' in
    pg_get_functiondef('public.audit_admin_bonus_insert()'::regprocedure)) > 0
  and position('transaction_audit' in
    pg_get_functiondef('public.audit_admin_bonus_insert()'::regprocedure)) > 0,
  'admin bonus audit records identify the transaction and action'
);

select ok(
  position('new.approved_by' in
    pg_get_functiondef('public.audit_admin_bonus_insert()'::regprocedure)) > 0
  and position('new.amount' in
    pg_get_functiondef('public.audit_admin_bonus_insert()'::regprocedure)) > 0
  and position('new.currency' in
    pg_get_functiondef('public.audit_admin_bonus_insert()'::regprocedure)) > 0,
  'audit event records the approving admin and currency-specific amount'
);

select * from finish();
rollback;
