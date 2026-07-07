-- D2 마무리: 기간형 기록 제출에도 사진 증빙(evidence_url)을 남길 수 있도록 submit_play 확장.
-- 사진은 Phase C와 동일하게 보조 증빙일 뿐 자동 판독하지 않는다.
-- 매개변수 개수가 바뀌므로(6→7) 기존 함수를 먼저 지우고 새로 만든다.

drop function if exists submit_play(uuid, uuid, int, int, text, date);

create or replace function submit_play(
  p_token uuid, p_player_id uuid, p_course_no int, p_strokes_total int,
  p_store text default null, p_played_at date default current_date, p_evidence_url text default null
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

  insert into plays (tournament_id, stage_id, player_id, course_no, strokes_total, played_at, store, source, evidence_url, entered_by)
  values (v_player.tournament_id, v_stage_id, p_player_id, p_course_no, p_strokes_total, p_played_at, p_store,
    case when p_evidence_url is not null then 'photo' else 'staff' end, p_evidence_url, v_staff.id);
end;
$$;
grant execute on function submit_play(uuid, uuid, int, int, text, date, text) to anon;
