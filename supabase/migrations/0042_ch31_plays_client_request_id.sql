-- CH31③ (A2-2): submit_play 응답이 유실돼 클라이언트가 "실패"로 표시해도 서버에는
-- 이미 커밋됐을 수 있다. 같은 client_request_id(멱등키)로 재조회해 실제 저장 여부를
-- 확인하려면 get_plays_for_staff가 client_request_id를 돌려줘야 한다.
-- 롤백: 0042_ch31_plays_client_request_id_ROLLBACK.sql

-- ── 실행 전 확인(선택) ──
--   select oid::regprocedure from pg_proc where proname='get_plays_for_staff'; → 1행(uuid 파라미터)

drop function if exists get_plays_for_staff(uuid);
create or replace function get_plays_for_staff(p_token uuid)
returns table(id uuid, player_id uuid, stage_id uuid, course_no int, strokes_total int,
  played_at date, created_at timestamptz, client_request_id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_tid uuid;
begin
  select st.tournament_id into v_tid from staff st where st.token = p_token;
  if v_tid is null then return; end if;
  return query
    select p.id, p.player_id, p.stage_id, p.course_no, p.strokes_total, p.played_at, p.created_at, p.client_request_id
    from plays p where p.tournament_id = v_tid;
end;
$$;
grant execute on function get_plays_for_staff(uuid) to anon;

-- ── 실행 후 확인 ──
--   select client_request_id from get_plays_for_staff('<judge-token>') limit 1; → 컬럼 존재, 에러 없음
