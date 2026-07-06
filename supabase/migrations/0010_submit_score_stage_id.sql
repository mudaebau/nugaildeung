-- D1 후속: submit_score가 scores.stage_id를 함께 채우도록 갱신.
-- 대회의 1단계(seq=1) stage를 찾아 넣는다 — 다단계(D2)가 도입되기 전까지는 항상 1단계뿐이다.

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

  select id into v_stage_id from stages where tournament_id = v_player.tournament_id order by seq limit 1;

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
