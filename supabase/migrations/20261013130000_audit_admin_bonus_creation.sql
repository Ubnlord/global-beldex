begin;

-- Future admin-issued USD/BDX bonuses must carry transaction-level audit linkage.
-- This intentionally does not backfill historical rows: absent contemporaneous
-- evidence, a synthetic audit event would falsely imply proof that does not exist.
create or replace function public.audit_admin_bonus_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.type = 'bonus'
     and new.method = 'admin'
     and new.status = 'completed'
     and new.approved_by is not null then
    insert into public.transaction_audit
      (transaction_id, admin_id, action, old_values, new_values, reason, created_at)
    values
      (
        new.id,
        new.approved_by,
        'admin_bonus_created',
        '{}'::jsonb,
        jsonb_build_object(
          'type', new.type,
          'amount', new.amount,
          'currency', coalesce(new.currency, 'USD'),
          'status', new.status,
          'approval_status', new.approval_status,
          'method', new.method
        ),
        coalesce(nullif(btrim(new.approval_reason), ''), nullif(btrim(new.note), ''), 'Admin bonus creation'),
        coalesce(new.created_at, now())
      );
  end if;
  return new;
end;
$function$;

revoke all on function public.audit_admin_bonus_insert() from public, anon, authenticated;

drop trigger if exists audit_admin_bonus_insert on public.transaction;
create trigger audit_admin_bonus_insert
after insert on public.transaction
for each row
execute function public.audit_admin_bonus_insert();

commit;
