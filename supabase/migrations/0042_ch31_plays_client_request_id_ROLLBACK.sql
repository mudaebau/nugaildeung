-- 0042_ch31_plays_client_request_id.sql 롤백 — client_request_id 노출 이전 버전으로 복귀

drop function if exists get_plays_for_staff(uuid);
create or replace function get_plays_for_staff(p_token uuid)
returns table(id uuid, player_id uuid, stage_id uuid, course_no int, strokes_total int,
  played_at date, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_tid uuid;
begin
  select st.tournament_id into v_tid from staff st where st.token = p_token;
  if v_tid is null then return; end if;
  return query
    select p.id, p.player_id, p.stage_id, p.course_no, p.strokes_total, p.played_at, p.created_at
    from plays p where p.tournament_id = v_tid;
end;
$$;
grant execute on function get_plays_for_staff(uuid) to anon;
