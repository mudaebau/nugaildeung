-- CH37-B: 단계 추가·삭제(허브 화면 7 v2 "⚙️ 대회 운영 → 🪜 대회 구조") — 순수 추가.
--
-- 왜 "꼬리 편집(A안)"인가 — players.current_stage가 stage_id가 아니라 seq 정수다(0011).
-- 중간 삽입·삭제로 seq를 재정렬하면 전 참가자의 소속 단계가 어긋나고, stages의
-- unique(tournament_id, seq) 때문에 재정렬 자체도 임시 오프셋 2단계 업데이트가 필요하다.
-- ⑰(진출 체인 붕괴)에서 확인했듯 이 매핑이 틀어지면 증상이 늦게·크게 터지므로,
-- 파일럿 전에는 재정렬이 아예 일어나지 않는 범위(맨 뒤 추가 / 마지막 단계만 삭제)로 제한한다.
-- 중간 삽입은 지원하지 않는다(사용자 승인된 제약). 훗날 필요하면 current_stage를
-- stage_id 참조로 바꾸는 선행 작업과 묶어서 처리한다.
--
-- 기존 함수는 하나도 건드리지 않는다(create_stages/open_stage/close_stage/advance_stage/
-- confirm_advance/confirm_stage_roster/update_stage_* 전부 무수정) — 운영(모바일 master)은
-- 단계 추가·삭제 UI가 없어 이 두 함수를 호출하지 않으므로 운영 영향 0.
-- 롤백: 0050_ch37_stage_add_delete_ROLLBACK.sql (drop function 2줄)

-- ── 실행 전 확인(선택) ──
--   select proname from pg_proc where proname in ('add_stage','delete_last_stage'); → 0행이어야 함

/* ① 단계 추가 — 항상 맨 뒤(seq = max+1). 재정렬 없음. */
create or replace function add_stage(t_id uuid, p_owner_secret uuid, p_stage jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_seq int;
  v_id uuid;
  v_kind text;
  v_record_mode text;
  v_name text;
  v_status text;
begin
  perform assert_owner(t_id, p_owner_secret);

  -- 종료된 대회는 구조를 못 바꾼다(가드 1)
  if exists (select 1 from tournaments where id = t_id and status = 'done') then
    raise exception '종료 확정된 대회는 단계를 추가할 수 없습니다';
  end if;

  -- jsonb 허용값 검증(가드 3) — 화이트리스트 밖 값은 즉시 거부한다.
  v_name        := nullif(btrim(coalesce(p_stage->>'name','')), '');
  v_kind        := coalesce(p_stage->>'kind','round');
  v_record_mode := coalesce(p_stage->>'record_mode','hole');
  if v_name is null then
    raise exception '단계 이름을 입력해 주세요';
  end if;
  if length(v_name) > 20 then
    raise exception '단계 이름은 20자 이내로 입력해 주세요';
  end if;
  if v_kind not in ('round','period') then
    raise exception '단계 방식이 올바르지 않습니다(round/period)';
  end if;
  if v_record_mode not in ('hole','total') then
    raise exception '기록 방식이 올바르지 않습니다(hole/total)';
  end if;
  -- 기간형은 총타 고정(CH35-B에서 확정된 제약)
  if v_kind = 'period' and v_record_mode <> 'total' then
    raise exception '기간형 단계는 총타수 제출만 지원합니다';
  end if;
  -- 새 단계는 항상 대기 상태로 만든다 — 임의 status 주입 금지
  v_status := 'waiting';

  select coalesce(max(seq), 0) + 1 into v_seq from stages where tournament_id = t_id;
  if v_seq > 6 then
    raise exception '단계는 최대 6개까지 만들 수 있습니다';
  end if;

  insert into stages(tournament_id, seq, name, kind, record_mode, date_start, date_end,
                     venues, course_pars, use_groups, tie_rule, advance_cut, status)
  values (t_id, v_seq, v_name, v_kind, v_record_mode,
          nullif(p_stage->>'date_start','')::date,
          nullif(p_stage->>'date_end','')::date,
          coalesce(p_stage->'venues', '[]'::jsonb),
          coalesce(p_stage->'course_pars', '[]'::jsonb),
          coalesce((p_stage->>'use_groups')::boolean, true),
          nullif(p_stage->>'tie_rule',''),
          p_stage->'advance_cut',
          v_status)
  returning id into v_id;

  -- 구조 변경은 수정 이력에 남긴다(가드 2)
  insert into tournament_edit_logs(tournament_id, who, what)
  values (t_id, coalesce(p_stage->>'who','운영자'),
          format('단계 추가 — %s(%s단계, %s·%s)', v_name, v_seq,
                 case v_kind when 'period' then '기간' else '지정일' end,
                 case v_record_mode when 'total' then '총타' else '홀별' end));

  return v_id;
end;
$$;
grant execute on function add_stage(uuid, uuid, jsonb) to anon;

/* ② 마지막 단계 삭제 — 마지막 seq만. 재정렬이 발생하지 않는 유일한 삭제 형태. */
create or replace function delete_last_stage(t_id uuid, p_owner_secret uuid, p_stage_id uuid, p_who text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_seq int;
  v_max int;
  v_status text;
  v_name text;
begin
  perform assert_owner(t_id, p_owner_secret);

  if exists (select 1 from tournaments where id = t_id and status = 'done') then
    raise exception '종료 확정된 대회는 단계를 삭제할 수 없습니다';
  end if;

  select seq, status, name into v_seq, v_status, v_name
    from stages where id = p_stage_id and tournament_id = t_id;
  if v_seq is null then
    raise exception '단계를 찾을 수 없습니다';
  end if;

  select max(seq) into v_max from stages where tournament_id = t_id;
  if v_seq <> v_max then
    raise exception '마지막 단계만 삭제할 수 있습니다 — 중간 단계를 지우면 참가자의 소속 단계가 어긋납니다';
  end if;
  if v_max <= 1 then
    raise exception '단계가 하나뿐이라 삭제할 수 없습니다';
  end if;
  if v_status <> 'waiting' then
    raise exception '이미 시작했거나 마감된 단계는 삭제할 수 없습니다';
  end if;

  -- 기록이 있으면 거부(P31 항목별 잠금과 같은 조건)
  if exists (select 1 from scores where stage_id = p_stage_id)
     or exists (select 1 from plays where stage_id = p_stage_id) then
    raise exception '이 단계에 기록이 있어 삭제할 수 없습니다';
  end if;
  -- 이미 이 단계로 올라온 참가자가 있으면 거부(진출자 확정을 되돌리는 건 별도 작업)
  if exists (select 1 from players where tournament_id = t_id and current_stage >= v_seq) then
    raise exception '이 단계 명단에 참가자가 있어 삭제할 수 없습니다 — 진출자 확정을 먼저 되돌리세요';
  end if;

  delete from stages where id = p_stage_id and tournament_id = t_id;

  insert into tournament_edit_logs(tournament_id, who, what)
  values (t_id, coalesce(p_who,'운영자'), format('단계 삭제 — %s(%s단계)', v_name, v_seq));
end;
$$;
grant execute on function delete_last_stage(uuid, uuid, uuid, text) to anon;

-- ── 실행 후 확인 ──
--   select oid::regprocedure from pg_proc where proname in ('add_stage','delete_last_stage'); → 2행
--   기존 함수 무변경 확인: create_stages/open_stage/close_stage/advance_stage/confirm_advance 그대로.
--   동작: add_stage는 seq=max+1로만 추가(최대 6), delete_last_stage는 마지막 seq·waiting·
--         기록 0·명단 0일 때만 삭제. 두 함수 모두 tournament_edit_logs에 기록을 남긴다.
