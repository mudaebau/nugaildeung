-- HOTFIX-P0: TECH-AUDIT-01 ⑥·⑩에서 발견된 anon 민감 컬럼 전면 노출 차단.
--   - staff.token: anon이 아무 대회의 심판 토큰이든 그냥 select로 읽어갈 수 있었다
--     (0024에서 이미 발견·문서화됐으나 당시 미조치로 보류됨 — 이번에 조치).
--   - players.phone: 참가자 전화번호가 마스킹 없이 전부 노출돼 있었다.
-- 조치 방식은 access_code(0024)·operators.secret(0026/0027)과 동일한 패턴:
-- 테이블 단위 select를 전량 회수한 뒤, 민감하지 않은 컬럼만 다시 연다.
-- token/phone처럼 "화면에는 필요하지만 원문이 필요없는" 값은 뷰(view)에서
-- 마스킹해 노출한다 — 클라이언트의 maskPhone()과 동일 규칙을 서버에도 둔다.
--
-- 하지 말 것(재사용 원칙): 기존 assert_owner/RLS 구조·다른 RPC는 그대로 두고,
-- 이 마이그레이션은 오직 staff/players의 select 경로만 다룬다.

-- ── 1) 전화번호 마스킹 헬퍼 (클라이언트 maskPhone()과 동일 규칙: 가운데 2자리만 가림) ──
create or replace function mask_phone(p text) returns text
language sql immutable as $$
  select regexp_replace(p, '([0-9]{3})-?([0-9]{2})[0-9]{2}-?([0-9]{4})', '\1-\2••-\3')
$$;

-- ── 2) staff: token/phone 컬럼 select 회수, 나머지만 재개방 ──
revoke select on staff from anon;
grant select (id, tournament_id, duty, can_score, link_opened_at) on staff to anon;

-- ── 3) players: phone 컬럼 select 회수, 나머지만 재개방 ──
revoke select on players from anon;
grant select (
  id, tournament_id, current_stage, name, sex, club, region, nick, age,
  status, group_no, group_order, created_at, checked_in_at, paid
) on players to anon;

-- ── 4) 마스킹된 phone을 포함하는 조회 전용 뷰 — 기존 클라이언트가 하던
--       sb.from('players').select(...) 자리를 그대로 대체한다(컬럼 이름 동일,
--       phone 값만 마스킹). 뷰는 소유자(이 마이그레이션 실행 롤) 권한으로
--       평가되므로 anon의 phone 컬럼 select 회수와 무관하게 내부적으로는
--       원문을 읽어 마스킹 후 반환할 수 있다.
create or replace view players_public as
select id, tournament_id, current_stage, name, mask_phone(phone) as phone,
  sex, club, region, nick, age, status, group_no, group_order, created_at,
  checked_in_at, paid
from players;
grant select on players_public to anon;

-- ── 5) 토큰 소지 자체가 인증인 심판 조회 RPC — 기존 직접
--       select('*').eq('token',token)를 대체. access_code/get_tournament_gated와
--       같은 원리(값을 이미 아는 사람만 그 값으로 조회 가능).
create or replace function get_staff_by_token(p_token uuid)
returns table(id uuid, tournament_id uuid, name text, phone text, duty text,
  can_score boolean, token uuid, link_opened_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  return query
    select s.id, s.tournament_id, s.name, mask_phone(s.phone), s.duty,
      s.can_score, s.token, s.link_opened_at
    from staff s where s.token = p_token;
end;
$$;
grant execute on function get_staff_by_token(uuid) to anon;

-- ── 6) 운영자 전용 심판 목록 조회 — token은 원문 그대로 돌려줘야 링크 생성이
--       가능하므로(judgeLink()), assert_owner로 소유자만 접근하게 막는다.
create or replace function get_staff_owner(t_id uuid, p_owner_secret uuid)
returns table(id uuid, name text, phone text, duty text, can_score boolean,
  token uuid, link_opened_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  return query
    select s.id, s.name, mask_phone(s.phone), s.duty, s.can_score, s.token, s.link_opened_at
    from staff s where s.tournament_id = t_id;
end;
$$;
grant execute on function get_staff_owner(uuid, uuid) to anon;

-- ── 7) 대회 개설 시 스탭 일괄 등록(운영자 전용) — 기존
--       sb.from('staff').insert(staffRows).select('id,token,phone')를 대체.
--       (token/phone select 회수 후에는 INSERT...RETURNING도 해당 컬럼을
--       돌려줄 권한이 없어 그대로 두면 깨진다.)
create or replace function create_staff_batch(t_id uuid, p_owner_secret uuid, p_staff jsonb)
returns table(id uuid, token uuid, phone text)
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  return query
    insert into staff (tournament_id, name, phone, duty, can_score)
    select t_id, s->>'name', s->>'phone', s->>'duty', coalesce((s->>'can_score')::boolean, true)
    from jsonb_array_elements(p_staff) as s
    returning staff.id, staff.token, staff.phone;
end;
$$;
grant execute on function create_staff_batch(uuid, uuid, jsonb) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- 확인 쿼리 안내
-- 주의: SQL 에디터 세션은 보통 postgres(관리자) 권한으로 연결되므로, 아래
-- select 문을 그냥 실행하면 anon 권한 여부와 무관하게 전부 "성공"해 버려서
-- 검증이 안 된다. 실제 anon 기준으로 확인하려면 둘 중 하나로 해야 한다:
--   (A) SQL 에디터에서 쿼리 앞에 `set role anon;` 을 먼저 실행한 뒤 같은 세션에서
--       select 실행(끝나면 `reset role;` 로 원복)
--   (B) 터미널/Postman 등에서 anon key로 REST 엔드포인트를 직접 호출
--       예: curl "$SUPABASE_URL/rest/v1/players?select=phone&limit=1" -H "apikey: $ANON_KEY"
--
-- 1) 실행 전 확인(취약 상태 재확인용, (A)/(B) 방식으로):
--   select token, phone from staff limit 1;   -- 지금은 그냥 보여야 함(문제 있는 상태 확인)
--   select phone from players limit 1;        -- 지금은 그냥 보여야 함
--
-- 2) 권한 카탈로그 확인(이건 관리자 세션에서 그대로 실행해도 됨 — anon 권한을
--    "조회"하는 것이지 "anon으로 실행"하는 게 아니므로):
--   select table_name, column_name, privilege_type from information_schema.column_privileges
--     where grantee='anon' and table_name in ('staff','players') order by 1,2;
--   -- staff: id,tournament_id,duty,can_score,link_opened_at 만 나와야 함(token/phone 없어야 함)
--   -- players: phone 빠지고 나머지 컬럼만 나와야 함
--
-- 3) 실행 후 확인((A) set role anon; 상태에서):
--   select * from players_public limit 3;     -- phone이 010-XX••-YYYY 형태로 보여야 함
--   select phone from players limit 1;        -- permission denied 나야 정상(회수 성공)
--   select token from staff limit 1;          -- permission denied 나야 정상(회수 성공)
--   reset role;
-- ══════════════════════════════════════════════════════════════════════════
