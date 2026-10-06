begin;

create or replace function public.admin_has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_user a
    where a.user_id = auth.uid()
      and p_permission = any(coalesce(a.permissions, '{}'::text[]))
  );
$$;

revoke all on function public.admin_has_permission(text) from public, anon, authenticated;

commit;
