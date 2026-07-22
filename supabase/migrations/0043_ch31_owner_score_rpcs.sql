-- CH31⑩: 개설자(소유자)가 별도 심판 등록 없이 스스로 점수를 입력할 수 있게 한다.
-- 가짜 심판 row/토큰을 만드는 대신, 기존 submit_play/update_play_strokes/delete_play와
-- 완전히 같은 로직을 assert_owner(owner_secret) 인증으로 여는 별도 RPC 3종을 추가한다
-- (entered_by는 staff row가 없으므로 NULL — plays.entered_by는 nullable).
-- 롤백: 0043_ch31_owner_score_rpcs_ROLLBACK.sql

create or replace function submit_play_owner(
  t_id uuid, p_owner_secret uuid, p_player_id uuid, p_course_no int, p_strokes_total int,
  p_store text default null, p_played_at date default current_date, p_evidence_url text default null,
  p_client_request_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_player players%rowtype;
  v_stage stages%rowtype;
  v_status text;
  v_id uuid;
begin
  perform assert_owner(t_id, p_owner_secret);

  if p_client_request_id is not null then
    select id into v_id from plays where client_request_id = p_client_request_id;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> t_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  select status into v_status from tournaments where id = t_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 더 이상 기록을 입력할 수 없습니다';
  end if;

  select * into v_stage from stages
    where tournament_id = t_id
      and (kind = 'period' or record_mode = 'total') and status = 'open'
    order by seq limit 1;
  if v_stage.id is null then
    select * into v_stage from stages
      where tournament_id = t_id and (kind = 'period' or record_mode = 'total')
      order by seq limit 1;
  end if;
  if v_stage.id is null then
    raise exception '이 대회에는 기록 입력 가능한 단계가 없습니다';
  end if;

  if v_stage.kind = 'round' then
    delete from plays where stage_id = v_stage.id and player_id = p_player_id and course_no = p_course_no;
  end if;

  insert into plays (tournament_id, stage_id, player_id, course_no, strokes_total, played_at, store, source, evidence_url, entered_by, client_request_id)
  values (t_id, v_stage.id, p_player_id, p_course_no, p_strokes_total, p_played_at, p_store,
    case when p_evidence_url is not null then 'photo' else 'owner' end, p_evidence_url, null, p_client_request_id)
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function submit_play_owner(uuid, uuid, uuid, int, int, text, date, text, uuid) to anon;

create or replace function update_play_strokes_owner(t_id uuid, p_owner_secret uuid, p_play_id uuid, p_strokes_total int) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_play plays%rowtype;
  v_status text;
begin
  perform assert_owner(t_id, p_owner_secret);
  select * into v_play from plays where id = p_play_id;
  if v_play.id is null or v_play.tournament_id <> t_id then
    raise exception '해당 대회의 기록이 아닙니다';
  end if;
  select status into v_status from tournaments where id = t_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 기록을 수정할 수 없습니다';
  end if;
  if p_strokes_total < 18 or p_strokes_total > 200 then
    raise exception '총타수를 확인해 주세요';
  end if;
  update plays set strokes_total = p_strokes_total where id = p_play_id;
end;
$$;
grant execute on function update_play_strokes_owner(uuid, uuid, uuid, int) to anon;

create or replace function delete_play_owner(t_id uuid, p_owner_secret uuid, p_play_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_play plays%rowtype;
  v_status text;
begin
  perform assert_owner(t_id, p_owner_secret);
  select * into v_play from plays where id = p_play_id;
  if v_play.id is null or v_play.tournament_id <> t_id then
    raise exception '해당 대회의 기록이 아닙니다';
  end if;
  select status into v_status from tournaments where id = t_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 기록을 수정할 수 없습니다';
  end if;
  delete from plays where id = p_play_id;
end;
$$;
grant execute on function delete_play_owner(uuid, uuid, uuid) to anon;

-- CH31③(A2-2)의 실패-후-재조회 로직을 소유자 경로에서도 쓰려면 get_plays_owner가
-- id·client_request_id를 돌려줘야 한다(기존엔 최소 컬럼만 있었다).
drop function if exists get_plays_owner(uuid, uuid);
create or replace function get_plays_owner(t_id uuid, p_owner_secret uuid)
returns table(id uuid, player_id uuid, stage_id uuid, course_no int, strokes_total int, client_request_id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_owner(t_id, p_owner_secret);
  return query select p.id, p.player_id, p.stage_id, p.course_no, p.strokes_total, p.client_request_id from plays p where p.tournament_id = t_id;
end;
$$;
grant execute on function get_plays_owner(uuid, uuid) to anon;

-- ── 실행 후 확인 ──
--   select oid::regprocedure from pg_proc where proname like '%_owner' and proname like '%play%'; → 4행
