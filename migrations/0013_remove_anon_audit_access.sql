begin;

revoke select on table public.admin_action_audit from anon;

commit;
