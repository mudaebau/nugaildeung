-- D1: stages 구조 도입 (위험 구간 — 기존 데이터 무손실 이관)
-- 안전을 위해 tournaments.rounds/venues/course_pars/tie_rule 컬럼은 이번 단계에서 삭제하지 않는다.
-- (D2 완료 후, 모든 화면이 stages만 읽는 것을 재확인하고 별도 마이그레이션으로 정리 예정)

create table stages (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  seq int not null,
  name text not null default '본선',
  kind text not null default 'round',
  date_start date,
  date_end date,
  venues jsonb not null default '[]',
  course_pars jsonb not null default '[]',
  use_groups boolean not null default true,
  tie_rule text,
  advance_cut jsonb,
  status text not null default 'ready',
  unique (tournament_id, seq)
);

alter table stages enable row level security;
create policy "stages_select_public" on stages for select using (true);
create policy "stages_insert_anon" on stages for insert with check (true);
create policy "stages_update_anon" on stages for update using (true);

alter table scores add column if not exists stage_id uuid references stages(id);

-- 기존 대회마다 1단계(본선) 자동 생성 — venues/course_pars/tie_rule/기간을 tournaments에서 그대로 복사
insert into stages (tournament_id, seq, name, kind, date_start, date_end, venues, course_pars, use_groups, tie_rule, status)
select t.id, 1, '본선', 'round', t.date_start, t.date_end, t.venues, t.course_pars, true, t.tie_rule,
  case when t.status = 'done' then 'done' when t.status in ('live','open') then 'open' else 'waiting' end
from tournaments t
where not exists (select 1 from stages s where s.tournament_id = t.id);

-- 기존 scores를 해당 대회의 1단계로 백필
update scores s set stage_id = st.id
from stages st
where st.tournament_id = s.tournament_id and st.seq = 1 and s.stage_id is null;
