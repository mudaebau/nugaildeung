-- ROLLBACK of 0048 — 0046의 advance_stage(자동 마감 포함) 정의로 복원.
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
  update players set current_stage = v_next_seq, group_no = null, group_order = null
    where id = any(p_advanced_player_ids) and tournament_id = t_id;
  update stages set status = 'done' where id = cur_stage_id and tournament_id = t_id;
end;
$$;
