-- 0037 롤백 — CH28-A ①③ 되돌리기
-- ③: warned_info 구버전 오버로드는 이미 삭제된 상태라 복원 대상 없음(원치 않으면 실행 불필요)
-- ①: submit_play를 client_request_id 이전(0034) 시그니처로 되돌리고 컬럼·인덱스 제거

drop function if exists submit_play(uuid, uuid, int, int, text, date, text, uuid);
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

drop index if exists plays_client_request_id_key;
alter table plays drop column if exists client_request_id;

-- 확인:
-- select column_name from information_schema.columns where table_name='plays' and column_name='client_request_id'; → 0행이어야 함
