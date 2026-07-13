-- 차수25(위저드 재편) D항: "인원 제한 없음" 정원 옵션.
-- 기존 cap(int, not null) 컬럼은 그대로 두고 boolean 플래그만 추가한다 — 무제한일 때도
-- cap 컬럼에는 마지막으로 유효했던(또는 기본) 정수를 유지해, 나중에 "제한 걸기"로
-- 되돌릴 때 이전 정원 값을 그대로 이어받을 수 있게 한다(하지 말 것: 기존 cap 로직 재구현 금지
-- — cap_unlimited=false일 때는 기존 apply_to_tournament/promote_waitlist_player 등의
-- cap 비교 로직이 손 안 대고 그대로 동작).
alter table tournaments add column if not exists cap_unlimited boolean not null default false;

-- 0027에서 anon에 컬럼 단위로만 재개방했으므로, 새 컬럼도 명시적으로 포함해야 보인다
-- (테이블 단위 select를 다시 열지 않는 이유는 0027 참고 — access_code 노출 방지).
revoke select on tournaments from anon;
grant select (
  id, owner_id, name, host_org, date_start, date_end, rounds, venues, course_pars,
  tie_rule, cap, cap_unlimited, fields, awards, status, created_at, type, visibility, notice_extra, reg_closed
) on tournaments to anon;

-- 공개 신청: 무제한이면 정원 비교 없이 항상 'ok'(대기 없음).
create or replace function apply_to_tournament(
  t_id uuid, p_code text, p_name text, p_phone text, p_sex text, p_age int,
  p_club text, p_region text, p_nick text
) returns table(status text, player_id uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_tournament tournaments%rowtype;
  v_ok_count int;
  v_status text;
  v_id uuid;
begin
  select * into v_tournament from tournaments t where t.id = t_id for update;
  if v_tournament.id is null then
    raise exception '대회를 찾을 수 없습니다';
  end if;
  if v_tournament.visibility = 'private' and (p_code is null or p_code <> v_tournament.access_code) then
    raise exception '입장 비밀번호가 올바르지 않습니다';
  end if;
  if v_tournament.reg_closed then
    raise exception '접수가 마감되었습니다';
  end if;

  if v_tournament.cap_unlimited then
    v_status := 'ok';
  else
    select count(*) into v_ok_count from players p where p.tournament_id = t_id and p.status = 'ok';
    v_status := case when v_ok_count >= v_tournament.cap then 'wait' else 'ok' end;
  end if;

  insert into players(tournament_id, name, phone, sex, age, club, region, nick, status)
  values (t_id, p_name, p_phone, p_sex, p_age, p_club, p_region, p_nick, v_status)
  returning id into v_id;

  return query select v_status, v_id;
end;
$$;
grant execute on function apply_to_tournament(uuid,text,text,text,text,int,text,text,text) to anon;

-- 경고 등급 수정 RPC에 p_cap_unlimited·p_fields 추가(일정·정원·참여대상·공개설정·참가자
-- 정보 항목이 전부 "경고 후 수정" 등급으로 한 묶음이라 이 RPC 하나만 확장 — 신규 RPC
-- 만들지 않음). p_fields는 null이면 기존 값 유지(참가자 정보 항목을 다루지 않는
-- 기존 호출부들이 실수로 fields를 지우지 않도록).
drop function if exists update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,uuid,text,text,boolean);
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

-- 대기자 승격도 무제한 정원이면 cap 비교를 건너뛴다(차수25: 제한 해제 시 대기자 전원
-- 확정 처리 기능이 이 RPC를 재사용하므로, cap_unlimited를 모르면 남아있던 cap 값 때문에
-- 정상적인 승격까지 막힐 수 있음).
create or replace function promote_waitlist_player(t_id uuid, player_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cap int; v_unlimited boolean; v_ok_count int;
begin
  perform assert_owner(t_id, p_owner_secret);
  select cap, cap_unlimited into v_cap, v_unlimited from tournaments where id = t_id for update;
  if not v_unlimited then
    select count(*) into v_ok_count from players where tournament_id = t_id and status = 'ok';
    if v_ok_count >= v_cap then
      raise exception '정원이 가득 차 있어 승격할 수 없습니다';
    end if;
  end if;
  update players set status = 'ok' where id = player_id and tournament_id = t_id;
end;
$$;
grant execute on function promote_waitlist_player(uuid,uuid,uuid) to anon;
