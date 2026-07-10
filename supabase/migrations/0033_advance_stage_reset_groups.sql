-- 차수19 검증 중 발견: advance_stage가 진출자의 current_stage만 바꾸고
-- group_no/group_order를 그대로 남겨둬서, 새 단계의 조편성 화면이 "아직 조가
-- 없습니다" 빈 화면 대신 이전 단계의 조 배치가 뒤섞인 채로 나타났다(일부만 진출해
-- 조 구성이 깨진 상태). 새 단계는 항상 미배정 상태로 시작해야 하므로,
-- 진출자의 group_no/group_order를 null로 초기화한다.

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
  update stages set status = 'open' where id = next_stage_id and tournament_id = t_id;
end;
$$;
grant execute on function advance_stage(uuid,uuid,uuid,uuid,uuid[]) to anon;

-- 콜업(set_player_stage)도 같은 이유로 이전 단계의 group_no/group_order를 초기화한다.
create or replace function set_player_stage(t_id uuid, player_id uuid, p_owner_secret uuid, p_stage_seq int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update players set current_stage = p_stage_seq, group_no = null, group_order = null
    where id = player_id and tournament_id = t_id;
end;
$$;
grant execute on function set_player_stage(uuid,uuid,uuid,int) to anon;
