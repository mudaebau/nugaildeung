-- 0046 롤백 — advance_stage가 다시 다음 단계를 자동 open하고, open_stage/close_stage 제거,
-- finalize_tournament는 stages를 건드리지 않던 이전 동작으로.

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

drop function if exists open_stage(uuid,uuid,uuid);
drop function if exists close_stage(uuid,uuid,uuid);

drop function if exists finalize_tournament(uuid, uuid);
create or replace function finalize_tournament(t_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
begin
  perform assert_owner(t_id, p_owner_secret);
  select status into v_status from tournaments where id = t_id;
  if v_status is null then
    raise exception '대회를 찾을 수 없습니다';
  end if;
  if v_status <> 'live' then
    raise exception '진행중(LIVE) 상태의 대회만 확정할 수 있습니다 (현재 상태: %)', v_status;
  end if;
  update tournaments set status = 'done' where id = t_id;
end;
$$;
grant execute on function finalize_tournament(uuid, uuid) to anon;
