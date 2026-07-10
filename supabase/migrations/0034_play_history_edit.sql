-- 차수23 ②③: 총점 인라인 입력의 "실행 취소"와 기록 내역 시트(수정/삭제)를 위해
-- submit_play가 삽입한 행의 id를 반환하도록 바꾸고, 심판 토큰으로 특정 기록을
-- 수정/삭제할 수 있는 RPC를 추가한다.

drop function if exists submit_play(uuid, uuid, int, int, text, date, text);
create or replace function submit_play(
  p_token uuid, p_player_id uuid, p_course_no int, p_strokes_total int,
  p_store text default null, p_played_at date default current_date, p_evidence_url text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
  v_stage stages%rowtype;
  v_status text;
  v_id uuid;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 입력 권한이 없는 링크입니다';
  end if;
  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  select status into v_status from tournaments where id = v_player.tournament_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 더 이상 기록을 입력할 수 없습니다';
  end if;

  select * into v_stage from stages
    where tournament_id = v_player.tournament_id
      and (kind = 'period' or record_mode = 'total') and status = 'open'
    order by seq limit 1;
  if v_stage.id is null then
    select * into v_stage from stages
      where tournament_id = v_player.tournament_id and (kind = 'period' or record_mode = 'total')
      order by seq limit 1;
  end if;
  if v_stage.id is null then
    raise exception '이 대회에는 기록 입력 가능한 단계가 없습니다';
  end if;

  if v_stage.kind = 'round' then
    delete from plays where stage_id = v_stage.id and player_id = p_player_id and course_no = p_course_no;
  end if;

  insert into plays (tournament_id, stage_id, player_id, course_no, strokes_total, played_at, store, source, evidence_url, entered_by)
  values (v_player.tournament_id, v_stage.id, p_player_id, p_course_no, p_strokes_total, p_played_at, p_store,
    case when p_evidence_url is not null then 'photo' else 'staff' end, p_evidence_url, v_staff.id)
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function submit_play(uuid, uuid, int, int, text, date, text) to anon;

-- 기록 내역 시트: 특정 기록 삭제(실행 취소도 동일 경로 사용). 대회 종료 후에는 거부.
create or replace function delete_play(p_token uuid, p_play_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_play plays%rowtype;
  v_status text;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 입력 권한이 없는 링크입니다';
  end if;
  select * into v_play from plays where id = p_play_id;
  if v_play.id is null or v_play.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 기록이 아닙니다';
  end if;
  select status into v_status from tournaments where id = v_play.tournament_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 기록을 수정할 수 없습니다';
  end if;
  delete from plays where id = p_play_id;
end;
$$;
grant execute on function delete_play(uuid, uuid) to anon;

-- 기록 내역 시트: 특정 기록의 타수 수정.
create or replace function update_play_strokes(p_token uuid, p_play_id uuid, p_strokes_total int) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_play plays%rowtype;
  v_status text;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 입력 권한이 없는 링크입니다';
  end if;
  select * into v_play from plays where id = p_play_id;
  if v_play.id is null or v_play.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 기록이 아닙니다';
  end if;
  select status into v_status from tournaments where id = v_play.tournament_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 기록을 수정할 수 없습니다';
  end if;
  if p_strokes_total < 18 or p_strokes_total > 200 then
    raise exception '총타수를 확인해 주세요';
  end if;
  update plays set strokes_total = p_strokes_total where id = p_play_id;
end;
$$;
grant execute on function update_play_strokes(uuid, uuid, int) to anon;
