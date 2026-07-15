-- CH28-C1 ②: 운영자 secret 재발급(=긴급 무효화, 새 값 발급 순간 구 값은 어떤 조회에도
-- 안 걸려 즉시 무효). B2의 reissue_staff_token과 동일한 "새 값 발급=구 값 즉시 사망"
-- 패턴 재사용(신규 개념 아님).
--
-- 인증 수준 참고: operator_signup과 동일하게 phone 하나로 재발급을 허용한다. 이 프로젝트의
-- 운영자 로그인 자체가 아직 문자 OTP 서버 검증 없는 간이 인증이라(docs/05-data-model.md
-- "한계(인지)" 항목, 정식 오픈 전 실제 OTP 예정) 여기서 phone 대신 구 secret을 요구해도
-- 진짜 "잃어버린 기기의 secret이 유출된" 비상 상황은 못 막는다 — 즉 phone 기반이 이
-- 기능의 목적(긴급 무효화)에 실질적으로 맞다. secret 기반 인증으로 올리는 건 실제 OTP
-- 도입과 함께 다룰 별도 과제.
create or replace function reissue_operator_secret(p_phone text)
returns table(id uuid, name text, secret uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  return query
    update operators o set secret = gen_random_uuid()
    where o.phone = p_phone
    returning o.id, o.name, o.secret;
end;
$$;
grant execute on function reissue_operator_secret(text) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- 검증:
-- 1) select * from reissue_operator_secret('<테스트 운영자 전화>');  -- 새 secret 반환
-- 2) 구 secret으로 아무 assert_owner 경유 RPC(update_player 등) 호출 → 거부돼야 함
-- 3) 새 secret으로 같은 RPC 호출 → 정상 동작해야 함
-- 4) 없는 전화번호로 호출 시 0행(에러 아님, 존재 여부 오라클 최소화)
-- ══════════════════════════════════════════════════════════════════════════
