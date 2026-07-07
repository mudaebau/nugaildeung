-- D2 후속: 다단계(예선→결승) 지원.
-- 1) submit_score/submit_play가 "현재 활성 단계"(status='open')를 찾도록 수정
--    (기존엔 seq=1로 고정되어 있어 2단계로 넘어가도 계속 1단계에 점수가 쌓였다)
-- 2) 기존 stage 행들의 status를 문서 규격(waiting/open/done)에 맞게 정리 — 'ready'는 'open'으로 간주

update stages set status = 'open' where status = 'ready';

create or replace function submit_score(
  p_token uuid, p_player_id uuid, p_hole_index int, p_strokes int, p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
  v_stage_id uuid;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 점수 입력 권한이 없는 링크입니다';
  end if;

  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  select id into v_stage_id from stages
    where tournament_id = v_player.tournament_id and status = 'open' order by seq limit 1;
  if v_stage_id is null then
    select id into v_stage_id from stages where tournament_id = v_player.tournament_id order by seq limit 1;
  end if;

  perform set_config('app.score_reason', coalesce(p_reason,''), true);

  if p_strokes is null then
    delete from scores where player_id = p_player_id and hole_index = p_hole_index;
  else
    insert into scores (tournament_id, stage_id, player_id, hole_index, strokes, entered_by, updated_at)
    values (v_player.tournament_id, v_stage_id, p_player_id, p_hole_index, p_strokes, v_staff.id, now())
    on conflict (player_id, hole_index)
    do update set strokes = excluded.strokes, stage_id = excluded.stage_id, entered_by = excluded.entered_by, updated_at = now();
  end if;
end;
$$;
grant execute on function submit_score(uuid, uuid, int, int, text) to anon;

create or replace function submit_play(
  p_token uuid, p_player_id uuid, p_course_no int, p_strokes_total int,
  p_store text default null, p_played_at date default current_date
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
  v_stage_id uuid;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 입력 권한이 없는 링크입니다';
  end if;
  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  select id into v_stage_id from stages
    where tournament_id = v_player.tournament_id and kind = 'period' and status = 'open' order by seq limit 1;
  if v_stage_id is null then
    select id into v_stage_id from stages
      where tournament_id = v_player.tournament_id and kind = 'period' order by seq limit 1;
  end if;
  if v_stage_id is null then
    raise exception '이 대회에는 기간형 단계가 없습니다';
  end if;

  insert into plays (tournament_id, stage_id, player_id, course_no, strokes_total, played_at, store, source, entered_by)
  values (v_player.tournament_id, v_stage_id, p_player_id, p_course_no, p_strokes_total, p_played_at, p_store, 'staff', v_staff.id);
end;
$$;
grant execute on function submit_play(uuid, uuid, int, int, text, date) to anon;
