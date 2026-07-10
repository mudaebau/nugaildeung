-- 차수16 ③: 대회가 종료(done)된 뒤에는 심판 토큰이 여전히 유효하더라도
-- submit_score/submit_play가 기록을 받지 않도록 막는다.
-- (기존에는 토큰·참가자 유효성만 검사하고 대회 상태는 확인하지 않았다.)

create or replace function submit_score(
  p_token uuid, p_player_id uuid, p_hole_index int, p_strokes int, p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
  v_stage_id uuid;
  v_status text;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 점수 입력 권한이 없는 링크입니다';
  end if;

  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  select status into v_status from tournaments where id = v_player.tournament_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 더 이상 기록을 입력할 수 없습니다';
  end if;

  select id into v_stage_id from stages
    where tournament_id = v_player.tournament_id and status = 'open' order by seq limit 1;
  if v_stage_id is null then
    select id into v_stage_id from stages where tournament_id = v_player.tournament_id order by seq limit 1;
  end if;

  perform set_config('app.score_reason', coalesce(p_reason,''), true);

  if p_strokes is null then
    delete from scores where stage_id = v_stage_id and player_id = p_player_id and hole_index = p_hole_index;
  else
    insert into scores (tournament_id, stage_id, player_id, hole_index, strokes, entered_by, updated_at)
    values (v_player.tournament_id, v_stage_id, p_player_id, p_hole_index, p_strokes, v_staff.id, now())
    on conflict (stage_id, player_id, hole_index)
    do update set strokes = excluded.strokes, entered_by = excluded.entered_by, updated_at = now();
  end if;
end;
$$;
grant execute on function submit_score(uuid, uuid, int, int, text) to anon;

create or replace function submit_play(
  p_token uuid, p_player_id uuid, p_course_no int, p_strokes_total int,
  p_store text default null, p_played_at date default current_date, p_evidence_url text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
  v_stage stages%rowtype;
  v_status text;
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
    case when p_evidence_url is not null then 'photo' else 'staff' end, p_evidence_url, v_staff.id);
end;
$$;
grant execute on function submit_play(uuid, uuid, int, int, text, date, text) to anon;
