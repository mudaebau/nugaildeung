-- 차수19 ②: 다음 단계 시작 후 명단을 조정(추가/제외)하고 명시적으로 확정해야만
-- 조편성이 가능하도록 하는 게이트. 1단계(예선)는 등록 명단이 그대로 명단이므로
-- 이 게이트를 적용하지 않는다(클라이언트에서 stage.seq===1을 항상 확정된 것으로 취급).

alter table stages add column if not exists roster_confirmed boolean not null default false;

create or replace function confirm_stage_roster(t_id uuid, stage_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update stages set roster_confirmed = true where id = stage_id and tournament_id = t_id;
end;
$$;
grant execute on function confirm_stage_roster(uuid,uuid,uuid) to anon;

-- 콜업: 이전 단계에 머물러 있는(진출하지 못한) 참가자를 현재 단계 명단으로 불러온다.
create or replace function set_player_stage(t_id uuid, player_id uuid, p_owner_secret uuid, p_stage_seq int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update players set current_stage = p_stage_seq where id = player_id and tournament_id = t_id;
end;
$$;
grant execute on function set_player_stage(uuid,uuid,uuid,int) to anon;
