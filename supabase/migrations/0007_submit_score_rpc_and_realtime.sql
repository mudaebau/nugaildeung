-- 6단계: 점수 입력 실시간
-- 클라이언트는 scores 테이블에 직접 쓸 수 있는 권한이 없다 (RLS에 anon insert/update 정책 없음).
-- 오직 submit_score RPC를 통해서만 점수를 쓸 수 있고, 그 안에서 심판 토큰을 검증한다.
-- scores 변경(추가/수정/삭제)은 트리거가 자동으로 score_logs에 남긴다 — 클라이언트가 누락해도 이력이 남는다.

create or replace function log_score_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_reason text := nullif(current_setting('app.score_reason', true), '');
begin
  if TG_OP = 'INSERT' then
    insert into score_logs (tournament_id, player_id, hole_index, old_strokes, new_strokes, reason, entered_by)
    values (NEW.tournament_id, NEW.player_id, NEW.hole_index, null, NEW.strokes, v_reason, NEW.entered_by);
  elsif TG_OP = 'UPDATE' then
    insert into score_logs (tournament_id, player_id, hole_index, old_strokes, new_strokes, reason, entered_by)
    values (NEW.tournament_id, NEW.player_id, NEW.hole_index, OLD.strokes, NEW.strokes, v_reason, NEW.entered_by);
  elsif TG_OP = 'DELETE' then
    insert into score_logs (tournament_id, player_id, hole_index, old_strokes, new_strokes, reason, entered_by)
    values (OLD.tournament_id, OLD.player_id, OLD.hole_index, OLD.strokes, null, v_reason, OLD.entered_by);
  end if;
  return null;
end;
$$;

drop trigger if exists scores_audit_log on scores;
create trigger scores_audit_log
after insert or update or delete on scores
for each row execute function log_score_change();

create or replace function submit_score(
  p_token uuid, p_player_id uuid, p_hole_index int, p_strokes int, p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 점수 입력 권한이 없는 링크입니다';
  end if;

  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  perform set_config('app.score_reason', coalesce(p_reason,''), true);

  if p_strokes is null then
    delete from scores where player_id = p_player_id and hole_index = p_hole_index;
  else
    insert into scores (tournament_id, player_id, hole_index, strokes, entered_by, updated_at)
    values (v_player.tournament_id, p_player_id, p_hole_index, p_strokes, v_staff.id, now())
    on conflict (player_id, hole_index)
    do update set strokes = excluded.strokes, entered_by = excluded.entered_by, updated_at = now();
  end if;
end;
$$;

grant execute on function submit_score(uuid, uuid, int, int, text) to anon;

-- 전광판이 scores/players 변경을 실시간 구독할 수 있도록 Realtime 발행 목록에 추가 (이미 있으면 건너뜀)
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='scores') then
    alter publication supabase_realtime add table scores;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='players') then
    alter publication supabase_realtime add table players;
  end if;
end $$;
