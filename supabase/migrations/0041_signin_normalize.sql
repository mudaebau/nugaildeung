-- SIGNIN 차수 ①: 전화번호 표기 정규화(서버) + 재방문 자동 로그인 지원.
--
-- 배경: 2차 실기기 검증에서 "재로그인 시 내 대회 실종"(P1)이 재현됐다. 원인 조사 결과
-- operator_signup의 on conflict(phone)이 문자열 완전 일치에만 의존하는데, 클라이언트
-- 어디에도 전화번호 정규화가 없었다(참가자 신청 경로 submitSingle()은 이미 정규화하고
-- 있었음 — 로그인 경로에만 빠져 있었다). 같은 사람이 하이픈 유무·공백 등 표기만
-- 다르게 입력하면 operators 행이 새로 생겨 owner_id가 달라지고, "내 대회"(owner_id 기준
-- 필터)가 통째로 사라지는 것까지 실제로 재현해 확인했다.
--
-- 조치: normalize_phone()로 참가자 경로와 동일한 규칙(숫자만 추출 후 3-4-4/3-3-4 하이픈)을
-- 서버에서도 적용 — 표기가 뭐든 저장 시점에 하나로 통일한다. 기존에 이미 저장된 phone
-- 값은 이 마이그레이션에서 건드리지 않는다(중복 병합은 별도 차수 — 실행 전 중복 조회
-- 결과를 먼저 확인하기로 함, 기존 unique 제약과 충돌 위험이 있어 신중하게 별도 처리).
--
-- 곁들여 operator_signup 반환에 is_new(신규 가입 여부)·active_count(진행 중 대회 수)를
-- 추가하고, 저장된 secret이 유효한지 이름 갱신 없이 조회만 하는 operator_session_check를
-- 신설 — SIGNIN 새 화면(장면1 시작하기/장면2 재방문 인사)이 이 값들로 분기한다.

create or replace function normalize_phone(p_phone text) returns text
language sql immutable as $$
  select regexp_replace(regexp_replace(p_phone, '[^0-9]', '', 'g'), '^(\d{3})(\d{3,4})(\d{4})$', '\1-\2-\3')
$$;

drop function if exists operator_signup(text, text);
create or replace function operator_signup(p_phone text, p_name text)
returns table(id uuid, name text, secret uuid, is_new boolean, active_count int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_phone text := normalize_phone(p_phone);
begin
  return query
    with upserted as (
      insert into operators as o (phone, name) values (v_phone, p_name)
      on conflict (phone) do update set name = excluded.name
      returning o.id, o.name, o.secret, (xmax = 0) as is_new
    )
    select u.id, u.name, u.secret, u.is_new,
      (select count(*)::int from tournaments t where t.owner_id = u.id and t.status <> 'done')
    from upserted u;
end;
$$;
grant execute on function operator_signup(text, text) to anon;

-- 재방문 자동 로그인: 저장된 (전화, secret) 쌍이 여전히 유효한지 이름 갱신 없이 조회만
-- 한다 — reissue_operator_secret으로 무효화된 뒤라면 0행을 반환해 클라이언트가 저장된
-- 값을 지우고 장면1(시작하기)로 되돌아가게 한다.
create or replace function operator_session_check(p_phone text, p_secret uuid)
returns table(id uuid, name text, active_count int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_phone text := normalize_phone(p_phone);
begin
  return query
    select o.id, o.name,
      (select count(*)::int from tournaments t where t.owner_id = o.id and t.status <> 'done')
    from operators o where o.phone = v_phone and o.secret = p_secret;
end;
$$;
grant execute on function operator_session_check(text, uuid) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- 검증:
-- 1) 표기 3종 동일 계정 확인:
--   select * from operator_signup('010-1234-5678','검증'); -- id 기록
--   select * from operator_signup('01012345678','검증');    -- 위와 동일 id, is_new=false
--   select * from operator_signup('010 1234 5678','검증');  -- 위와 동일 id, is_new=false
-- 2) 신규 가입 확인: 전혀 새 번호로 operator_signup 호출 → is_new=true, active_count=0
-- 3) 세션 확인: select * from operator_session_check('010-1234-5678','<위에서 받은 secret>');
--    -- 1행 반환. 틀린 secret으로 호출 시 0행.
-- 4) reissue_operator_secret 호출 후 구 secret으로 operator_session_check 재호출 → 0행
-- ══════════════════════════════════════════════════════════════════════════
