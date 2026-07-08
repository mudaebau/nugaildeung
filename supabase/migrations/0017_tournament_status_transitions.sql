-- 대회 상태(ready/open → live → done) 전환을 DB 쪽에서만 처리한다.
-- tournaments에는 UPDATE RLS 정책을 절대 열지 않는다 — 대신
-- ① scores/plays에 기록이 들어오면 트리거가 자동으로 live 전환
-- ② 결과 확정은 finalize_tournament RPC(security definer)로만, live일 때만 done으로.
-- 둘 다 status 컬럼만 건드리고 다른 컬럼은 절대 바꾸지 않는다.

create or replace function activate_tournament_on_record() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update tournaments set status = 'live'
    where id = new.tournament_id and status in ('ready','open');
  return new;
end;
$$;

drop trigger if exists trg_scores_activate on scores;
create trigger trg_scores_activate after insert on scores
  for each row execute function activate_tournament_on_record();

drop trigger if exists trg_plays_activate on plays;
create trigger trg_plays_activate after insert on plays
  for each row execute function activate_tournament_on_record();

create or replace function finalize_tournament(t_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
begin
  select status into v_status from tournaments where id = t_id;
  if v_status is null then
    raise exception '대회를 찾을 수 없습니다';
  end if;
  if v_status <> 'live' then
    raise exception '진행중(LIVE) 상태의 대회만 확정할 수 있습니다 (현재 상태: %)', v_status;
  end if;
  update tournaments set status = 'done' where id = t_id;
end;
$$;
grant execute on function finalize_tournament(uuid) to anon;
