-- CH35-A ⑦/⑰: 진출자 확정(advance_stage)과 단계 마감(close_stage) 커플링 제거.
-- 기존 advance_stage는 진출자를 다음 단계로 올리면서 현재 단계를 자동으로 status='done' 처리했다.
-- 이 자동 마감 때문에, 진출자 확정 없이 [마감]을 먼저 누르거나 확정 결과가 이상할 때
-- (3단계 대회) 현재 단계는 done인데 아무도 다음 seq로 못 가 → loadPrimaryStage가 다음
-- waiting 단계를 primary로 잡고 그 단계 명단(current_stage=next_seq)이 0명 → 참가자 소실.
-- 해법: advance_stage는 "진출자 이동"만. 마감은 반드시 별도 close_stage로만.
-- (함수 재정의 — 스키마 추가/변경 없음. 롤백은 0046 정의로 복원.)
-- 롤백: 0048_ch35_advance_no_autoclose_ROLLBACK.sql

create or replace function advance_stage(
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
  -- 진출자만 다음 단계 명단으로(조 배치 초기화). 현재 단계는 여기서 닫지 않는다 —
  -- 마감은 close_stage가 담당(확정↔마감 분리, CH35-A⑦).
  update players set current_stage = v_next_seq, group_no = null, group_order = null
    where id = any(p_advanced_player_ids) and tournament_id = t_id;
end;
$$;

-- ── 실행 후 확인 ──
--   진출자 확정 시 현재 단계 status가 'open' 그대로인지(자동 done 아님), 진출자 current_stage만 바뀌는지.
