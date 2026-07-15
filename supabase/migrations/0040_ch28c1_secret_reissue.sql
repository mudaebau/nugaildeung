-- CH28-C1 ②: 운영자 secret 재발급(=긴급 무효화).
--
-- 1차 설계 오류(사용자 리뷰로 발견): 새 secret을 RPC 응답에 직접 반환했었다 —
-- phone은 사실상 공개에 가까운 정보라, 그 설계면 "전화번호만 알면 계정 탈취"가
-- 되는 구조였다. 무효화(보안 기능)가 그 자체로 로그인과 동급의 새 구멍을 만드는
-- 셈이라 절대 불가 판정.
--
-- 수정된 설계: 이 RPC는 "무효화"만 한다 — 새 값을 반환하지 않는다(성공 여부만).
-- 새 값을 실제로 받으려면 반드시 기존 operator_signup(phone, name) 로그인
-- 플로우(전화 입력 → OTP 확인 → 이름 입력)를 다시 거쳐야 한다. operator_signup은
-- 이미 phone만으로 "현재" secret을 반환하는 기존 로그인 경로이므로(간이 인증의
-- 기존 기준선, docs/05-data-model.md "한계(인지)" 항목 — 정식 OTP는 별도 과제),
-- 이 마이그레이션이 그 노출을 새로 넓히지 않는다. 무효화와 수신을 분리해두면
-- 공격자가 재발급을 트리거해도 얻는 건 "피해자 로그아웃"뿐 — 새 값은 못 가져간다
-- (수용 가능한 잔여 위험: 반복 호출로 인한 로그아웃 골탕/DoS, 아래 쿨다운으로 완화).
alter table operators add column if not exists secret_reissued_at timestamptz;

create or replace function reissue_operator_secret(p_phone text)
returns void
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_last timestamptz;
begin
  select o.secret_reissued_at into v_last from operators o where o.phone = p_phone;
  if v_last is not null and now() - v_last < interval '60 seconds' then
    raise exception '잠시 후 다시 시도해 주세요(연속 재발급 방지, 60초)';
  end if;
  update operators o set secret = gen_random_uuid(), secret_reissued_at = now()
  where o.phone = p_phone;
end;
$$;
grant execute on function reissue_operator_secret(text) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- 검증:
-- 1) select secret from operators where phone='<테스트 운영자 전화>'; 로 재발급 전 값 기록
-- 2) select reissue_operator_secret('<테스트 운영자 전화>');  -- 반환값 없음(성공만)
-- 3) select secret from operators where phone='<테스트 운영자 전화>'; -- 1)과 달라야 함
-- 4) 구 secret으로 아무 assert_owner 경유 RPC(update_player 등) 호출 → 거부돼야 함
-- 5) select * from operator_signup('<테스트 운영자 전화>','<기존 이름>'); -- 3)의 새 secret과
--    동일한 값이 반환돼야 함(재로그인으로 새 값 수신 확인)
-- 6) 60초 이내 재호출 → "연속 재발급 방지" 예외 확인
-- 7) 없는 전화번호로 호출 시 조용히 종료(0행 업데이트, 에러 아님 — 존재 여부 오라클 최소화)
-- ══════════════════════════════════════════════════════════════════════════
