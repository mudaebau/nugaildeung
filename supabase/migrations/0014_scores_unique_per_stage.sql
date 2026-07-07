-- D2 후속 버그 수정: scores의 UNIQUE 제약이 (player_id, hole_index)만 보고 있어
-- 다단계 대회에서 결승 점수를 입력하면 예선 점수를 덮어써버리는 문제가 있었다.
-- (stage_id, player_id, hole_index)로 넓혀서 단계별로 별도 행이 되게 한다.

alter table scores drop constraint if exists scores_player_id_hole_index_key;
alter table scores add constraint scores_stage_player_hole_key unique (stage_id, player_id, hole_index);

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
