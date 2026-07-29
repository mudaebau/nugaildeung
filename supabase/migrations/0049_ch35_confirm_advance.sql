-- CH35-A ⑦/⑰: 콘솔 전용 "진출자 확정"(마감과 분리) — 순수 추가.
-- 운영(모바일)의 중간 단계 [마감]은 advance_stage의 자동 done에 의존한다(확인됨).
-- 따라서 advance_stage는 무수정 유지(모바일 전용)하고, 콘솔용 신규 함수 confirm_advance를
-- 하나 추가한다: 진출자만 다음 단계 명단으로 이동(current_stage), 현재 단계는 닫지 않는다.
-- 콘솔: 진출자 확정=confirm_advance, 단계 마감=close_stage(별도). 운영 영향 0.
-- 롤백: 0049_ch35_confirm_advance_ROLLBACK.sql (drop function)

create or replace function confirm_advance(
  t_id uuid, cur_stage_id uuid, next_stage_id uuid, p_owner_secret uuid, p_advanced_player_ids uuid[]
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_next_seq int;
begin
  perform assert_owner(t_id, p_owner_secret);
  select seq into v_next_seq from stages where id = next_stage_id and tournament_id = t_id;
  if v_next_seq is null then
    raise exception '다음 단계를 찾을 수 없습니다';
  end if;
  -- 진출자만 다음 단계 명단으로(조 배치 초기화). 현재 단계 status는 건드리지 않는다 —
  -- 마감은 close_stage가 담당(확정↔마감 분리). advance_stage(모바일)는 무수정.
  update players set current_stage = v_next_seq, group_no = null, group_order = null
    where id = any(p_advanced_player_ids) and tournament_id = t_id;
end;
$$;
grant execute on function confirm_advance(uuid,uuid,uuid,uuid,uuid[]) to anon;

-- ── 실행 후 확인 ──
--   confirm_advance 호출 시 현재 단계 status='open' 유지(자동 done 아님), 진출자 current_stage만 변경.
--   advance_stage는 변경 없음(모바일 중간 마감 = 자동 done 그대로).
