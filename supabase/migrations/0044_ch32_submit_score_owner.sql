-- CH32-A(보완 라운드) P1①②: 개설자(소유자)가 홀별(라운드형) 점수도 별도 심판 등록 없이
-- 스스로 입력할 수 있게 한다. CH31⑩(submit_play/update_play_strokes/delete_play owner 분기)이
-- submit_score(홀별 전용 RPC)는 빠뜨려서, 개설자가 홀별 입력 화면에서 저장을 눌러도
-- currentJudgeToken()이 null을 반환해 클라이언트가 조용히 아무 요청도 보내지 않고 있었다
-- (submitScoreToServer의 `if(!token||!playerId)return;` — 에러도 토스트도 없는 무반응).
-- 가짜 심판 row는 만들지 않고, submit_score와 완전히 같은 로직을 assert_owner 인증으로
-- 여는 별도 RPC를 추가한다(entered_by는 staff row가 없으므로 NULL).
-- 롤백: 0044_ch32_submit_score_owner_ROLLBACK.sql

-- ── 실행 전 확인(선택) ──
--   select oid::regprocedure from pg_proc where proname='submit_score_owner'; → 0행(신규)

create or replace function submit_score_owner(
  t_id uuid, p_owner_secret uuid, p_player_id uuid, p_hole_index int, p_strokes int, p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_player players%rowtype;
  v_stage_id uuid;
  v_status text;
begin
  perform assert_owner(t_id, p_owner_secret);

  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> t_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  select status into v_status from tournaments where id = t_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 더 이상 기록을 입력할 수 없습니다';
  end if;

  select id into v_stage_id from stages
    where tournament_id = t_id and status = 'open' order by seq limit 1;
  if v_stage_id is null then
    select id into v_stage_id from stages where tournament_id = t_id order by seq limit 1;
  end if;

  perform set_config('app.score_reason', coalesce(p_reason,''), true);

  if p_strokes is null then
    delete from scores where stage_id = v_stage_id and player_id = p_player_id and hole_index = p_hole_index;
  else
    insert into scores (tournament_id, stage_id, player_id, hole_index, strokes, entered_by, updated_at)
    values (t_id, v_stage_id, p_player_id, p_hole_index, p_strokes, null, now())
    on conflict (stage_id, player_id, hole_index)
    do update set strokes = excluded.strokes, entered_by = excluded.entered_by, updated_at = now();
  end if;
end;
$$;
grant execute on function submit_score_owner(uuid, uuid, uuid, int, int, text) to anon;

-- ── 실행 후 확인 ──
--   select oid::regprocedure from pg_proc where proname='submit_score_owner'; → 1행
--   (owner_secret으로) select submit_score_owner('<t_id>','<owner_secret>','<player_id>',0,4,null);
--   select * from scores where player_id='<player_id>' and hole_index=0; → strokes=4, entered_by is null
