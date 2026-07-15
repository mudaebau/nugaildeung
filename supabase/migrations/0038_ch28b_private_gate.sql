-- CH28-B: 비공개 대회 게이트형 RPC 전환 + 전화 마스킹 강화 + 운영자 원문 전화 경로.
-- TECH-AUDIT-01에서 HOTFIX-P0 범위로 보류된 항목("비공개 대회의 players/scores/plays
-- 노출은 구조 변경이 크면 CH28 편입") — 여기서 처리한다.
--
-- 문제: players/scores/plays(+players_public 뷰)는 지금 anon에게 using(true)로 전부
-- 열려 있다. get_tournament_gated의 "게이트"는 대회 메타데이터(이름 등)만 막고,
-- 실제 참가자/점수/기록은 tournament_id만 알면(URL에 그대로 노출됨) 코드 없이도
-- REST로 직접 읽힌다 — 비공개 대회의 핵심 취약점.
--
-- 방침(사용자 승인, 인벤토리 검토 완료):
--   ① RLS: players/scores/plays의 select 정책을 using(true) → "해당 대회
--      visibility='public'일 때만"으로 교체. 공개 대회를 읽는 기존 호출부는 무변경
--      동작(파손 0), 비공개 대회 행만 직접 조회에서 사라짐(빈 배열, 에러 아님).
--   ② 비공개 열람 = 게이트 RPC(get_*_gated, t_id+code) — 전광판·요강·신청 경로.
--      phone 컬럼 자체를 반환하지 않는다(용도상 불필요, 마스킹본조차 과다 노출).
--   ③ 운영자 경로 = assert_owner 검증 RPC(get_*_owner) — phone은 항상 마스킹본만
--      반환(원문은 get_player_phone 단건 경로로만, 통화 목적 최소 노출).
--   ④ 심판 경로 = 토큰 검증 RPC(get_players_for_staff/get_plays_for_staff) — 기존
--      get_staff_by_token과 동일 원리. scores는 심판이 직접 읽는 곳이 없어 대상 아님.
--
-- players_public 뷰 우회 함정: 뷰는 기본적으로 소유자(이 마이그레이션 실행 롤) 권한으로
-- 평가되므로, 기저 테이블에만 RLS 정책을 걸면 뷰 경유 조회가 그 정책을 우회해 비공개
-- 행이 그대로 보일 수 있다(0035류의 "드롭 시그니처 불일치"와 같은 급의 조용한 함정).
-- 대응: RLS 평가 방식에 기대지 않고 뷰 정의 자체에 visibility='public' 조건을
-- 내장한다 — 구조적으로 비공개 행이 결과셋에 아예 들어오지 않으므로 뷰 소유자가
-- 누구든, RLS가 어떻게 평가되든 안전. 검증 쿼리에 "anon으로 뷰 경유 비공개 대회
-- 조회 → 0행"을 반드시 포함(본문 하단).
--
-- 하지 말 것(재사용 원칙): get_tournament_gated/assert_owner/get_staff_by_token의
-- 기존 검증 로직·시그니처는 그대로 재사용. submit_play/submit_score 등 쓰기 RPC는
-- 이번 범위 아님(이미 토큰 검증됨).

-- ══════════════════════════════════════════════════════════════════════════
-- ① 전화 마스킹 강화 — 가운데 전부(2~4자리) 마스킹. players_public 뷰는 함수만
--    바꾸면 자동 반영.
-- ══════════════════════════════════════════════════════════════════════════
create or replace function mask_phone(p text) returns text
language sql immutable as $$
  select regexp_replace(p, '([0-9]{3})-?[0-9]{2,4}-?([0-9]{4})', '\1-••••-\2')
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- ② RLS 정책 교체 — players/scores/plays: using(true) → 공개 대회만
-- ══════════════════════════════════════════════════════════════════════════
drop policy if exists "players_select_public" on players;
create policy "players_select_public" on players for select
  using (exists (select 1 from tournaments t where t.id = players.tournament_id and t.visibility = 'public'));

drop policy if exists "scores_select_public" on scores;
create policy "scores_select_public" on scores for select
  using (exists (select 1 from tournaments t where t.id = scores.tournament_id and t.visibility = 'public'));

drop policy if exists "plays_select_public" on plays;
create policy "plays_select_public" on plays for select
  using (exists (select 1 from tournaments t where t.id = plays.tournament_id and t.visibility = 'public'));

-- ══════════════════════════════════════════════════════════════════════════
-- ③ players_public 뷰 재정의 — visibility='public' 조건을 뷰 정의 자체에 내장
--    (RLS 우회 함정 대응, 위 설명 참고). 컬럼 목록은 0036과 동일.
-- ══════════════════════════════════════════════════════════════════════════
create or replace view players_public as
select p.id, p.tournament_id, p.current_stage, p.name, mask_phone(p.phone) as phone,
  p.sex, p.club, p.region, p.nick, p.age, p.status, p.group_no, p.group_order, p.created_at,
  p.checked_in_at, p.paid
from players p
join tournaments t on t.id = p.tournament_id
where t.visibility = 'public';
grant select on players_public to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- ④ 게이트 RPC 3종 — t_id+code, get_tournament_gated와 동일한 판정식 재사용.
--    phone 컬럼 자체를 반환하지 않는다(전광판·요강·신청 헤드카운트는 불필요).
-- ══════════════════════════════════════════════════════════════════════════
create or replace function get_players_gated(t_id uuid, p_code text default null)
returns table(id uuid, tournament_id uuid, current_stage int, name text, sex text, club text,
  region text, nick text, age int, status text, group_no int, group_order int,
  created_at timestamptz, checked_in_at timestamptz, paid boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_t tournaments%rowtype;
begin
  -- RETURNS TABLE의 OUT 컬럼(id 등)이 함수 본문 전체에서 변수처럼 스코프돼 bare
  -- 컬럼명이 테이블 컬럼과 이름이 겹치면 "ambiguous"가 난다. 테이블 별칭도 같이
  -- 써두지만, 이 pragma로 애매하면 항상 테이블 컬럼 쪽을 우선하도록 명시적으로
  -- 고정한다(0.035류처럼 조용히 틀리는 대신 확실하게 정의된 동작으로 만듦).
  select * into v_t from tournaments tt where tt.id = t_id;
  if v_t.id is null or not (v_t.visibility = 'public' or (p_code is not null and p_code = v_t.access_code)) then
    return;
  end if;
  return query
    select p.id, p.tournament_id, p.current_stage, p.name, p.sex, p.club, p.region, p.nick,
      p.age, p.status, p.group_no, p.group_order, p.created_at, p.checked_in_at, p.paid
    from players p where p.tournament_id = t_id;
end;
$$;
grant execute on function get_players_gated(uuid, text) to anon;

create or replace function get_scores_gated(t_id uuid, p_code text default null)
returns table(player_id uuid, stage_id uuid, hole_index int, strokes int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_t tournaments%rowtype;
begin
  select * into v_t from tournaments tt where tt.id = t_id;
  if v_t.id is null or not (v_t.visibility = 'public' or (p_code is not null and p_code = v_t.access_code)) then
    return;
  end if;
  return query select s.player_id, s.stage_id, s.hole_index, s.strokes from scores s where s.tournament_id = t_id;
end;
$$;
grant execute on function get_scores_gated(uuid, text) to anon;

create or replace function get_plays_gated(t_id uuid, p_code text default null)
returns table(player_id uuid, stage_id uuid, course_no int, strokes_total int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_t tournaments%rowtype;
begin
  select * into v_t from tournaments tt where tt.id = t_id;
  if v_t.id is null or not (v_t.visibility = 'public' or (p_code is not null and p_code = v_t.access_code)) then
    return;
  end if;
  return query select p.player_id, p.stage_id, p.course_no, p.strokes_total from plays p where p.tournament_id = t_id;
end;
$$;
grant execute on function get_plays_gated(uuid, text) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- ⑤ 운영자 RPC 3종 — assert_owner 검증, phone은 항상 마스킹본만.
-- ══════════════════════════════════════════════════════════════════════════
create or replace function get_players_owner(t_id uuid, p_owner_secret uuid)
returns table(id uuid, tournament_id uuid, current_stage int, name text, phone text, sex text,
  club text, region text, nick text, age int, status text, group_no int, group_order int,
  created_at timestamptz, checked_in_at timestamptz, paid boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_owner(t_id, p_owner_secret);
  return query
    select p.id, p.tournament_id, p.current_stage, p.name, mask_phone(p.phone), p.sex, p.club,
      p.region, p.nick, p.age, p.status, p.group_no, p.group_order, p.created_at, p.checked_in_at, p.paid
    from players p where p.tournament_id = t_id;
end;
$$;
grant execute on function get_players_owner(uuid, uuid) to anon;

create or replace function get_scores_owner(t_id uuid, p_owner_secret uuid)
returns table(player_id uuid, stage_id uuid, hole_index int, strokes int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_owner(t_id, p_owner_secret);
  return query select s.player_id, s.stage_id, s.hole_index, s.strokes from scores s where s.tournament_id = t_id;
end;
$$;
grant execute on function get_scores_owner(uuid, uuid) to anon;

create or replace function get_plays_owner(t_id uuid, p_owner_secret uuid)
returns table(player_id uuid, stage_id uuid, course_no int, strokes_total int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_owner(t_id, p_owner_secret);
  return query select p.player_id, p.stage_id, p.course_no, p.strokes_total from plays p where p.tournament_id = t_id;
end;
$$;
grant execute on function get_plays_owner(uuid, uuid) to anon;

-- 통화 목적 전용 단건 원문 전화 경로(브랜치 B ③) — 명단 행 [전화 걸기] 버튼용.
-- get_players_owner는 절대 원문 phone을 섞지 않는다(위 마스킹본만) — 이 RPC 하나로만
-- 원문이 나가므로 노출 경로가 단일하고 감사하기 쉽다.
create or replace function get_player_phone(t_id uuid, player_id uuid, p_owner_secret uuid)
returns text
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_phone text;
begin
  perform assert_owner(t_id, p_owner_secret);
  select phone into v_phone from players where id = player_id and tournament_id = t_id;
  return v_phone;
end;
$$;
grant execute on function get_player_phone(uuid, uuid, uuid) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- ⑥ 심판(토큰) RPC 2종 — get_staff_by_token과 동일 원리(토큰 소지=인증).
--    scores는 심판이 직접 읽는 호출부가 없어(재접속 시 빈 스코어카드로 시작하는
--    기존 동작 그대로, 이번 범위 아님) 대상에서 제외.
-- ══════════════════════════════════════════════════════════════════════════
create or replace function get_players_for_staff(p_token uuid)
returns table(id uuid, tournament_id uuid, current_stage int, name text, phone text, sex text,
  club text, region text, nick text, age int, status text, group_no int, group_order int,
  created_at timestamptz, checked_in_at timestamptz, paid boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_tid uuid;
begin
  select st.tournament_id into v_tid from staff st where st.token = p_token;
  if v_tid is null then return; end if;
  return query
    select p.id, p.tournament_id, p.current_stage, p.name, mask_phone(p.phone), p.sex, p.club,
      p.region, p.nick, p.age, p.status, p.group_no, p.group_order, p.created_at, p.checked_in_at, p.paid
    from players p where p.tournament_id = v_tid;
end;
$$;
grant execute on function get_players_for_staff(uuid) to anon;

-- id/played_at/created_at 포함 — openPlayHistory(기록 내역 시트, 수정·삭제 대상 지정)가
-- 필요로 한다. get_plays_gated/owner는 그 화면이 없어 최소 컬럼만 유지(불필요 노출 방지).
create or replace function get_plays_for_staff(p_token uuid)
returns table(id uuid, player_id uuid, stage_id uuid, course_no int, strokes_total int,
  played_at date, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_tid uuid;
begin
  select st.tournament_id into v_tid from staff st where st.token = p_token;
  if v_tid is null then return; end if;
  return query
    select p.id, p.player_id, p.stage_id, p.course_no, p.strokes_total, p.played_at, p.created_at
    from plays p where p.tournament_id = v_tid;
end;
$$;
grant execute on function get_plays_for_staff(uuid) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- ⑦ apply_to_tournament 확장 — 대기번호를 같은 트랜잭션(행 잠금) 안에서 함께
--    반환. 기존 클라이언트는 신청 직후 별도 select로 대기번호를 셌는데(countStatus),
--    이제 players 테이블 RLS가 비공개 대회 행을 막으므로 그 후속 select가 깨진다.
--    반환값 확장으로 대체(재요청 자체가 필요 없어져 더 안전).
-- ══════════════════════════════════════════════════════════════════════════
-- RETURNS TABLE 컬럼 구성을 바꾸므로(2열→3열) create or replace만으로는 안 된다
-- ("cannot change return type of existing function") — 먼저 DROP 필수.
drop function if exists apply_to_tournament(uuid,text,text,text,text,int,text,text,text);
create or replace function apply_to_tournament(
  t_id uuid, p_code text, p_name text, p_phone text, p_sex text, p_age int,
  p_club text, p_region text, p_nick text
) returns table(status text, player_id uuid, wait_no int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_tournament tournaments%rowtype;
  v_ok_count int;
  v_status text;
  v_id uuid;
  v_wait_no int;
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

  if v_status = 'wait' then
    select count(*) into v_wait_no from players p where p.tournament_id = t_id and p.status = 'wait';
  end if;

  return query select v_status, v_id, v_wait_no;
end;
$$;
grant execute on function apply_to_tournament(uuid,text,text,text,text,int,text,text,text) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- 검증 쿼리 안내
-- SQL 에디터 세션은 postgres(관리자) 권한이라 RLS를 우회하므로, anon 기준 검증은
-- `set role anon;` 뒤에 실행하고 끝나면 `reset role;` 로 원복해야 한다.
--
-- 사전 준비(관리자 세션에서, 실제 비공개 대회 하나 있어야 함):
--   select id, visibility, access_code from tournaments where visibility='private' limit 1;
--   -- 위 id를 아래 <PRIVATE_ID>에 대입
--
-- 1) 뷰 우회 함정 확인 — 반드시 0행이어야 함(이번 마이그레이션의 핵심 검증):
--   set role anon;
--   select * from players_public where tournament_id = '<PRIVATE_ID>';  -- → 0행
--   select * from players where tournament_id = '<PRIVATE_ID>';        -- → 0행(RLS)
--   select * from scores where tournament_id = '<PRIVATE_ID>';         -- → 0행(RLS)
--   select * from plays where tournament_id = '<PRIVATE_ID>';          -- → 0행(RLS)
--   reset role;
--
-- 2) 게이트 RPC — 코드 없이 0행, 올바른 코드로 정상 반환(phone 컬럼 자체가 없어야 함):
--   set role anon;
--   select * from get_players_gated('<PRIVATE_ID>', null);             -- → 0행
--   select * from get_players_gated('<PRIVATE_ID>', '<올바른 코드>');   -- → N행, phone 컬럼 없음
--   reset role;
--
-- 3) 공개 대회는 전부 무변경 동작 확인:
--   set role anon;
--   select id from tournaments where visibility='public' limit 1;      -- <PUBLIC_ID>
--   select * from players_public where tournament_id = '<PUBLIC_ID>' limit 3;  -- 그대로 나와야 함
--   reset role;
--
-- 4) 마스킹 강화 확인:
--   set role anon;
--   select phone from players_public where tournament_id = '<PUBLIC_ID>' limit 1;
--   -- 010-••••-1234 형태(가운데 4자리 전부)여야 함, 기존 010-XX••-1234 아님
--   reset role;
-- ══════════════════════════════════════════════════════════════════════════
