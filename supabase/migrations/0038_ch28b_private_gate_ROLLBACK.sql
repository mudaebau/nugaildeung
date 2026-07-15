-- 0038 롤백 — CH28-B 게이트 RPC 전환·마스킹 강화·전화 걸기 RPC 되돌리기.
-- 주의: 롤백하면 비공개 대회의 players/scores/plays가 다시 anon에게 전면 노출된다
-- (using(true)로 복귀). 긴급 상황에서만 사용.

-- 신규 RPC 전부 제거
drop function if exists get_players_gated(uuid, text);
drop function if exists get_scores_gated(uuid, text);
drop function if exists get_plays_gated(uuid, text);
drop function if exists get_players_owner(uuid, uuid);
drop function if exists get_scores_owner(uuid, uuid);
drop function if exists get_plays_owner(uuid, uuid);
drop function if exists get_player_phone(uuid, uuid, uuid);
drop function if exists get_players_for_staff(uuid);
drop function if exists get_plays_for_staff(uuid);

-- apply_to_tournament: wait_no 확장 이전(0035) 시그니처로 복원
drop function if exists apply_to_tournament(uuid,text,text,text,text,int,text,text,text);
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

-- players_public: visibility 조건 없는 0036 정의로 복원
create or replace view players_public as
select id, tournament_id, current_stage, name, mask_phone(phone) as phone,
  sex, club, region, nick, age, status, group_no, group_order, created_at,
  checked_in_at, paid
from players;
grant select on players_public to anon;

-- RLS 정책: using(true)로 복원(0001/0011 원래 상태)
drop policy if exists "players_select_public" on players;
create policy "players_select_public" on players for select using (true);

drop policy if exists "scores_select_public" on scores;
create policy "scores_select_public" on scores for select using (true);

drop policy if exists "plays_select_public" on plays;
create policy "plays_select_public" on plays for select using (true);

-- 마스킹: 0036의 2자리 마스킹으로 복원
create or replace function mask_phone(p text) returns text
language sql immutable as $$
  select regexp_replace(p, '([0-9]{3})-?([0-9]{2})[0-9]{2}-?([0-9]{4})', '\1-\2••-\3')
$$;

-- 확인: 아래가 다시 열려야(= 예전처럼 노출) 롤백 성공
-- set role anon;
-- select * from players where tournament_id = '<PRIVATE_ID>';  -- 다시 보여야 함
-- reset role;
