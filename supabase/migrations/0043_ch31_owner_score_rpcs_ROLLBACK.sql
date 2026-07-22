-- 0043_ch31_owner_score_rpcs.sql 롤백

drop function if exists submit_play_owner(uuid, uuid, uuid, int, int, text, date, text, uuid);
drop function if exists update_play_strokes_owner(uuid, uuid, uuid, int);
drop function if exists delete_play_owner(uuid, uuid, uuid);

drop function if exists get_plays_owner(uuid, uuid);
create or replace function get_plays_owner(t_id uuid, p_owner_secret uuid)
returns table(player_id uuid, stage_id uuid, course_no int, strokes_total int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_owner(t_id, p_owner_secret);
  return query select p.player_id, p.stage_id, p.course_no, p.strokes_total from plays p where p.tournament_id = t_id;
end;
$$;
grant execute on function get_plays_owner(uuid, uuid) to anon;
