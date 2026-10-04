-- Milestone 2.1: keep Supabase Auth signup from failing when user_profile RLS is enabled.
-- The auth.users trigger must insert the initial profile with controlled definer privileges.

create or replace function public.ensure_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.user_profile (
    user_id,
    username,
    fullname,
    phone,
    country
  )
  values (
    new.id,
    nullif(new.raw_user_meta_data->>'username',''),
    nullif(new.raw_user_meta_data->>'full_name',''),
    nullif(new.raw_user_meta_data->>'phone',''),
    nullif(new.raw_user_meta_data->>'country','')
  )
  on conflict (user_id) do update set
    username = coalesce(excluded.username, public.user_profile.username),
    fullname = coalesce(excluded.fullname, public.user_profile.fullname),
    phone = coalesce(excluded.phone, public.user_profile.phone),
    country = coalesce(excluded.country, public.user_profile.country),
    updated_at = now();

  return new;
end;
$function$;

revoke all on function public.ensure_user_profile() from public;
revoke all on function public.ensure_user_profile() from anon;
revoke all on function public.ensure_user_profile() from authenticated;
grant execute on function public.ensure_user_profile() to postgres;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row
execute function public.ensure_user_profile();
