-- 0045_ch32_venue_place.sql 롤백 — p_venue_place 파라미터 이전 시그니처로 되돌림

drop function if exists update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,uuid,text,text,boolean,jsonb,text);
create or replace function update_tournament_warned_info(
  t_id uuid, p_date_start date, p_date_end date, p_cap int,
  p_eligibility jsonb, p_visibility text, p_access_code text, p_owner_secret uuid,
  p_who text, p_what text, p_cap_unlimited boolean default false, p_fields jsonb default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update tournaments set
    date_start = p_date_start, date_end = p_date_end, cap = p_cap, cap_unlimited = p_cap_unlimited,
    visibility = p_visibility,
    access_code = case when p_visibility = 'private' then p_access_code else null end,
    notice_extra = coalesce(notice_extra,'{}'::jsonb) || jsonb_build_object('eligibility', p_eligibility),
    fields = coalesce(p_fields, fields)
  where id = t_id;
  insert into tournament_edit_logs(tournament_id, who, what) values (t_id, p_who, p_what);
end;
$$;
grant execute on function update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,uuid,text,text,boolean,jsonb) to anon;
