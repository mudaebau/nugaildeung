-- ROLLBACK of 0053 — 트리거 4개 + 함수 제거. RPC 2종의 done 가드도 되돌린다.
-- ⚠️ 되돌리면 종료된 대회가 다시 수정 가능해진다(P23C-1 정책 해제).

drop trigger if exists trg_readonly_done_players on players;
drop trigger if exists trg_readonly_done_scores  on scores;
drop trigger if exists trg_readonly_done_plays   on plays;
drop trigger if exists trg_readonly_done_stages  on stages;
drop function if exists assert_tournament_not_done();

-- 요강 편집 RPC를 0053 이전(가드 없음) 본문으로 되돌린다.
create or replace function update_tournament_free_info(
  t_id uuid, p_name text, p_host_org text, p_awards jsonb,
  p_prize_total text, p_prizes jsonb, p_contact text, p_fee text, p_rules text,
  p_owner_secret uuid, p_who text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update tournaments set
    name = p_name, host_org = p_host_org, awards = p_awards,
    notice_extra = coalesce(notice_extra,'{}'::jsonb) || jsonb_build_object(
      'prize_total', p_prize_total, 'prizes', p_prizes,
      'contact', p_contact, 'fee', p_fee, 'rules', p_rules)
  where id = t_id;
  insert into tournament_edit_logs(tournament_id, who, what)
    values (t_id, p_who, '기본 정보 수정 (대회명·주최·시상·요강정보)');
end;
$$;

create or replace function update_tournament_warned_info(
  t_id uuid, p_date_start date, p_date_end date, p_cap int,
  p_eligibility jsonb, p_visibility text, p_access_code text, p_owner_secret uuid,
  p_who text, p_what text, p_cap_unlimited boolean default false, p_fields jsonb default null,
  p_venue_place text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update tournaments set
    date_start = p_date_start, date_end = p_date_end, cap = p_cap, cap_unlimited = p_cap_unlimited,
    visibility = p_visibility,
    access_code = case when p_visibility = 'private' then p_access_code else null end,
    notice_extra = coalesce(notice_extra,'{}'::jsonb)
      || jsonb_build_object('eligibility', p_eligibility)
      || case when p_venue_place is not null then jsonb_build_object('venue_place', p_venue_place) else '{}'::jsonb end,
    fields = coalesce(p_fields, fields)
  where id = t_id;
  insert into tournament_edit_logs(tournament_id, who, what) values (t_id, p_who, p_what);
end;
$$;

-- notify pgrst, 'reload schema';
