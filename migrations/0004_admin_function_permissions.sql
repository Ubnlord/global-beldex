-- Restrict admin control functions to authenticated callers.
revoke execute on function public.admin_search_users(text,integer) from public, anon;
revoke execute on function public.admin_set_user_block(uuid,boolean,text) from public, anon;
revoke execute on function public.admin_update_investment(uuid,numeric,boolean) from public, anon;

grant execute on function public.admin_search_users(text,integer) to authenticated;
grant execute on function public.admin_set_user_block(uuid,boolean,text) to authenticated;
grant execute on function public.admin_update_investment(uuid,numeric,boolean) to authenticated;
