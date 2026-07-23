-- CH32-A(보완 라운드) ⑧: 대회장소(요강·신청 표시용 텍스트)를 코스명(scores 데이터와
-- 연결된 stages.venues)과 분리한다. 새 컬럼을 추가하지 않고 기존 tournaments.notice_extra
-- jsonb에 'venue_place' 키를 추가하는 방식 — contact/fee/rules/apply_deadline과 동일한 패턴.
-- update_tournament_warned_info(일정 편집 RPC)에 p_venue_place 파라미터를 추가한다.
-- 기본값 null로 하위호환 유지(구버전 클라이언트가 이 파라미터 없이 호출해도 동작).
-- 롤백: 0045_ch32_venue_place_ROLLBACK.sql

-- ── 실행 전 확인(선택) ──
--   select oid::regprocedure from pg_proc where proname='update_tournament_warned_info';
--   → update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,uuid,text,text,boolean,jsonb) 1행

drop function if exists update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,uuid,text,text,boolean,jsonb);
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
grant execute on function update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,uuid,text,text,boolean,jsonb,text) to anon;

-- ── 실행 후 확인 ──
--   select oid::regprocedure from pg_proc where proname='update_tournament_warned_info'; → 1행(신규 시그니처)
--   select notice_extra->>'venue_place' from tournaments where id='<t_id>'; → 저장한 값 확인
