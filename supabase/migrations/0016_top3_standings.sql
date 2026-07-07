-- v2.1 Phase E 5차: 홈 LIVE 카드용 미니 리더보드.
-- 전체 점수를 클라이언트로 불러와 정렬하지 않고, 서버에서 상위 3명만 계산해 반환한다.
-- 라운드형(scores 합산)과 기간형(plays: 코스별 최저타 합산)을 모두 지원.

create or replace function top3_standings(p_tournament_id uuid)
returns table(player_id uuid, name text, sex text, total int)
language sql stable as $$
  with cur_stage as (
    select id, kind from stages
    where tournament_id = p_tournament_id
    order by (status = 'open') desc, seq desc
    limit 1
  ),
  round_totals as (
    select p.id as player_id, p.name, p.sex, sum(s.strokes)::int as total
    from players p
    join scores s on s.player_id = p.id
    join cur_stage cs on cs.id = s.stage_id and cs.kind = 'round'
    where p.tournament_id = p_tournament_id and p.status = 'ok'
    group by p.id, p.name, p.sex
  ),
  period_best as (
    select pl.player_id, pl.course_no, min(pl.strokes_total) as best
    from plays pl
    join cur_stage cs on cs.id = pl.stage_id and cs.kind = 'period'
    group by pl.player_id, pl.course_no
  ),
  period_totals as (
    select p.id as player_id, p.name, p.sex, sum(pb.best)::int as total
    from players p
    join period_best pb on pb.player_id = p.id
    where p.tournament_id = p_tournament_id and p.status = 'ok'
    group by p.id, p.name, p.sex
  )
  select * from round_totals
  union all
  select * from period_totals
  order by total asc
  limit 3
$$;

grant execute on function top3_standings(uuid) to anon;
