-- D2 (최소 종단 흐름): 기간형(period) 단계의 기록을 저장하는 plays 테이블.
-- kind='round'는 기존 scores를 그대로 쓰고, kind='period'만 plays를 쓴다.
-- 진출 컷/단계 전환(players.current_stage 활용)은 이번 범위에서 제외 — 다음에 별도 진행.

alter table players add column if not exists current_stage int not null default 1;

create table plays (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  stage_id uuid not null references stages(id) on delete cascade,
  player_id uuid not null references players(id) on delete cascade,
  course_no int not null,
  strokes_total int not null check (strokes_total between 18 and 200),
  played_at date not null default current_date,
  store text,
  source text not null default 'staff',
  evidence_url text,
  entered_by uuid references staff(id),
  created_at timestamptz not null default now()
);

alter table plays enable row level security;
-- 전광판이 공개로 읽어야 하므로 읽기는 공개. 쓰기는 submit_play RPC로만(토큰 검증), 직접 insert 권한은 열지 않는다.
create policy "plays_select_public" on plays for select using (true);

create or replace function submit_play(
  p_token uuid, p_player_id uuid, p_course_no int, p_strokes_total int,
  p_store text default null, p_played_at date default current_date
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
  v_stage_id uuid;
begin
  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 입력 권한이 없는 링크입니다';
  end if;

  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  select id into v_stage_id from stages
    where tournament_id = v_player.tournament_id and kind = 'period' order by seq limit 1;
  if v_stage_id is null then
    raise exception '이 대회에는 기간형 단계가 없습니다';
  end if;

  insert into plays (tournament_id, stage_id, player_id, course_no, strokes_total, played_at, store, source, entered_by)
  values (v_player.tournament_id, v_stage_id, p_player_id, p_course_no, p_strokes_total, p_played_at, p_store, 'staff', v_staff.id);
end;
$$;

grant execute on function submit_play(uuid, uuid, int, int, text, date) to anon;
