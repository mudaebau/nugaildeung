-- 차수9: 기록 입력 방식 옵션(홀별/총점만). 라운드 단계도 record_mode='total'이면
-- plays 테이블을 재사용한다(기간형과 달리 코스당 1회만 유지 — 재입력 시 기존 값 대체).

alter table stages add column if not exists record_mode text not null default 'hole';

drop function if exists submit_play(uuid, uuid, int, int, text, date, text);
create or replace function submit_play(
  p_token uuid, p_player_id uuid, p_course_no int, p_strokes_total int,
  p_store text default null, p_played_at date default current_date, p_evidence_url text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
  v_stage stages%rowtype;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 입력 권한이 없는 링크입니다';
  end if;
  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 참가자가 아닙니다';
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

  -- 라운드 단계(총점만)는 코스당 1회만 유지 — 재입력은 기존 값을 대체한다.
  if v_stage.kind = 'round' then
    delete from plays where stage_id = v_stage.id and player_id = p_player_id and course_no = p_course_no;
  end if;

  insert into plays (tournament_id, stage_id, player_id, course_no, strokes_total, played_at, store, source, evidence_url, entered_by)
  values (v_player.tournament_id, v_stage.id, p_player_id, p_course_no, p_strokes_total, p_played_at, p_store,
    case when p_evidence_url is not null then 'photo' else 'staff' end, p_evidence_url, v_staff.id);
end;
$$;
grant execute on function submit_play(uuid, uuid, int, int, text, date, text) to anon;
