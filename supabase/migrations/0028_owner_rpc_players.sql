-- 차수21 ①: players 테이블에 대한 anon 직접 insert/update를 전부 없애고
-- 소유자 검증(assert_owner, 0026)을 거치는 RPC로 대체한다.
--
-- 참고: savePEdit()/setPStatus()/promoteWait()/delPlayer()는 기존에 로컬 상태만 바꾸고
-- 서버에 반영되지 않던(새로고침하면 사라지는) 버그가 있었다 — 이번에 RPC로 옮기면서 함께
-- 실제로 저장되도록 고친다(차수21 완료 기준의 회귀 테스트 대상에 포함).

create or replace function add_player(
  t_id uuid, p_owner_secret uuid, p_name text, p_phone text, p_sex text, p_age int,
  p_club text, p_region text, p_nick text, p_status text default 'ok'
) returns players
language plpgsql security definer set search_path = public as $$
declare
  v_row players%rowtype;
begin
  perform assert_owner(t_id, p_owner_secret);
  insert into players(tournament_id, name, phone, sex, age, club, region, nick, status)
  values (t_id, p_name, p_phone, p_sex, p_age, p_club, p_region, p_nick, coalesce(p_status,'ok'))
  returning * into v_row;
  return v_row;
end;
$$;
grant execute on function add_player(uuid,uuid,text,text,text,int,text,text,text,text) to anon;

-- 이름/성별/나이/소속 수정, 기권·실격·복귀, 체크인, 입금 여부를 한 번에 처리하는 부분 갱신 RPC.
-- null인 인자는 "바꾸지 않음"을 의미한다.
create or replace function update_player(
  t_id uuid, player_id uuid, p_owner_secret uuid,
  p_name text default null, p_sex text default null, p_age int default null, p_club text default null,
  p_status text default null, p_checked_in boolean default null, p_paid boolean default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update players set
    name = coalesce(p_name, name),
    sex = coalesce(p_sex, sex),
    age = coalesce(p_age, age),
    club = coalesce(p_club, club),
    status = coalesce(p_status, status),
    checked_in_at = case when p_checked_in is null then checked_in_at
                         when p_checked_in then now() else null end,
    paid = coalesce(p_paid, paid)
  where id = player_id and tournament_id = t_id;
end;
$$;
grant execute on function update_player(uuid,uuid,uuid,text,text,int,text,text,boolean,boolean) to anon;

-- 대기자 승격: 정원 초과 여부를 서버에서 다시 확인한 뒤 확정 처리한다(동시 승격 경쟁 방지).
create or replace function promote_waitlist_player(t_id uuid, player_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cap int; v_ok_count int;
begin
  perform assert_owner(t_id, p_owner_secret);
  select cap into v_cap from tournaments where id = t_id for update;
  select count(*) into v_ok_count from players where tournament_id = t_id and status = 'ok';
  if v_ok_count >= v_cap then
    raise exception '정원이 가득 차 있어 승격할 수 없습니다';
  end if;
  update players set status = 'ok' where id = player_id and tournament_id = t_id;
end;
$$;
grant execute on function promote_waitlist_player(uuid,uuid,uuid) to anon;

-- 참가자 삭제: 이미 입력된 점수/기록이 있으면 삭제 대신 기권 처리를 유도한다(데이터 무결성 보호).
create or replace function delete_player(t_id uuid, p_player_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  if exists(select 1 from scores s where s.player_id = p_player_id)
     or exists(select 1 from plays pl where pl.player_id = p_player_id) then
    raise exception '이미 기록이 입력된 참가자는 삭제할 수 없습니다 — 기권 처리를 이용하세요';
  end if;
  delete from players where id = p_player_id and tournament_id = t_id;
end;
$$;
grant execute on function delete_player(uuid,uuid,uuid) to anon;

-- 조편성 일괄 반영. p_assignments: [{"id":"uuid","group_no":0,"group_order":0}, ...]
create or replace function set_group_assignments(t_id uuid, p_owner_secret uuid, p_assignments jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update players p set
    group_no = (a.item->>'group_no')::int,
    group_order = (a.item->>'group_order')::int
  from jsonb_array_elements(p_assignments) as a(item)
  where p.id = (a.item->>'id')::uuid and p.tournament_id = t_id;
end;
$$;
grant execute on function set_group_assignments(uuid,uuid,jsonb) to anon;
