begin;

-- is_admin is an authorization helper, not a public information endpoint.
revoke all on function public.is_admin() from public, anon, authenticated;
grant execute on function public.is_admin() to authenticated, service_role;

-- Pin the permission helper's lookup path as defense in depth.
alter function public.admin_has_permission(text)
  set search_path = pg_catalog, public, pg_temp;

-- A user can have at most one administrator record.
alter table public.admin_user
  add constraint admin_user_user_id_unique unique (user_id);

commit;
