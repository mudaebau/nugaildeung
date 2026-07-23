-- CH32-B 보완: 단계 "마감 · 시작 · 종료 확정"을 분리한다.
-- 기존엔 advance_stage가 이전 단계를 done으로 만들면서 다음 단계를 곧바로 open으로 열었고
-- (마감=자동 시작), 마지막 단계는 finalize_tournament가 대회를 바로 done으로 확정했다
-- (마감=자동 종료). 그 결과 여정에서 "예선 마감 → 결승 [시작]"·"결승 마감 → [종료 확정]"
-- 같은 단계적 포커스 이동이 불가능했고, finalize가 stages.status를 건드리지 않아 마지막
-- 단계 줄에 활성 파랑 [마감] 버튼이 잔존했다(P22·P23 위반).
--   ① advance_stage: 다음 단계를 자동으로 열지 않는다(waiting 유지) — 컷 산출·이전 단계 done만.
--   ② open_stage(신규): 사전 점검 통과 후 [시작]이 호출 — waiting→open, 순서 강제.
--   ③ close_stage(신규): 마지막 단계 [마감]이 호출 — open→done(다음 단계 없음, 컷 없음).
--   ④ finalize_tournament: 잔여 open 단계를 방어적으로 done 처리한 뒤 대회를 done으로.
-- 롤백: 0046_ch32b_stage_lifecycle_ROLLBACK.sql

-- ── ① advance_stage: 다음 단계 자동 open 제거 ──
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
  -- 진출자를 다음 단계 명단으로(조 배치는 초기화 — 새 단계는 미배정에서 시작)
  update players set current_stage = v_next_seq, group_no = null, group_order = null
    where id = any(p_advanced_player_ids) and tournament_id = t_id;
  -- 현재 단계만 마감. 다음 단계는 waiting 그대로 두고, [결승 시작] 사전 점검 후 open_stage로 연다.
  update stages set status = 'done' where id = cur_stage_id and tournament_id = t_id;
end;
$$;
grant execute on function advance_stage(uuid,uuid,uuid,uuid,uuid[]) to anon;

-- ── ② open_stage: 대기 단계를 연다(순서 강제) ──
create or replace function open_stage(t_id uuid, stage_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_seq int;
begin
  perform assert_owner(t_id, p_owner_secret);
  select seq into v_seq from stages where id = stage_id and tournament_id = t_id;
  if v_seq is null then
    raise exception '단계를 찾을 수 없습니다';
  end if;
  if v_seq > 1 and exists(select 1 from stages where tournament_id = t_id and seq < v_seq and status <> 'done') then
    raise exception '이전 단계를 먼저 마감해야 시작할 수 있습니다';
  end if;
  update stages set status = 'open' where id = stage_id and tournament_id = t_id and status = 'waiting';
end;
$$;
grant execute on function open_stage(uuid,uuid,uuid) to anon;

-- ── ③ close_stage: 진행 중 단계를 마감(다음 단계 없는 마지막 단계용) ──
create or replace function close_stage(t_id uuid, stage_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update stages set status = 'done' where id = stage_id and tournament_id = t_id and status = 'open';
end;
$$;
grant execute on function close_stage(uuid,uuid,uuid) to anon;

-- ── ④ finalize_tournament: 잔여 open 단계 방어적 close 후 대회 확정 ──
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
  update stages set status = 'done' where tournament_id = t_id and status <> 'done';
  update tournaments set status = 'done' where id = t_id;
end;
$$;
grant execute on function finalize_tournament(uuid, uuid) to anon;

-- ── 실행 후 확인 ──
--   select oid::regprocedure from pg_proc where proname in ('open_stage','close_stage'); → 2행
--   (2단계 대회) 예선 마감 후: select status from stages order by seq; → done, waiting
--   결승 [시작] 후: → done, open   /  결승 마감 후: → done, done  /  종료 확정 후 대회 done
