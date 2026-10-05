begin;

create unique index if not exists transaction_welcome_bonus_uq
  on public.transaction(user_id)
  where type='bonus' and method='Welcome Bonus';

create or replace function public.ensure_user_profile(
  p_username text,
  p_fullname text,
  p_phone text default '',
  p_country text default '',
  p_ref text default null
)
returns public.user_profile
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_profile public.user_profile;
  v_ref uuid;
  v_code text;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if coalesce(trim(p_username),'')='' then raise exception 'Username is required'; end if;

  if p_ref is not null and trim(p_ref)<>'' then
    select user_id into v_ref
    from public.user_profile
    where lower(username)=lower(trim(p_ref))
       or lower(coalesce(referral_code,''))=lower(trim(p_ref))
    limit 1;
    if v_ref=v_uid then raise exception 'Cannot refer yourself'; end if;
  end if;

  v_code := lower(regexp_replace(trim(p_username),'[^a-zA-Z0-9_-]','','g'));
  if v_code='' then v_code := substr(replace(v_uid::text,'-',''),1,12); end if;

  insert into public.user_profile(
    user_id,username,fullname,phone,country,referral_code,referred_by_user_id,updated_at
  )
  values(
    v_uid,trim(p_username),coalesce(nullif(trim(p_fullname),''),trim(p_username)),
    coalesce(p_phone,''),coalesce(p_country,''),v_code,v_ref,now()
  )
  on conflict (user_id) do update set
    username=coalesce(nullif(excluded.username,''),public.user_profile.username),
    fullname=coalesce(nullif(trim(excluded.fullname),''),public.user_profile.fullname),
    phone=excluded.phone,
    country=excluded.country,
    referral_code=coalesce(public.user_profile.referral_code,excluded.referral_code),
    referred_by_user_id=coalesce(public.user_profile.referred_by_user_id,excluded.referred_by_user_id),
    updated_at=now()
  returning * into v_profile;

  if not exists (
    select 1 from public.transaction
    where user_id=v_uid and type='bonus' and method='Welcome Bonus'
  ) then
    update public.user_profile
      set available_balance=available_balance+3, updated_at=now()
      where user_id=v_uid
      returning * into v_profile;

    insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
    values(v_uid,'bonus',3,'completed','approved','Welcome Bonus','Server-side welcome bonus');
  end if;

  return v_profile;
end;
$function$;

revoke execute on function public.swap_assets(text,text,numeric,numeric) from public, anon, authenticated;

commit;
