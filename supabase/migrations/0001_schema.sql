-- 누가일등 2단계: 기본 스키마
-- operators / tournaments / staff / players / scores / score_logs
-- 적용 방법: Supabase 대시보드 → SQL Editor → 이 파일 내용 붙여넣기 → Run

create extension if not exists pgcrypto;

create table operators (
  id uuid primary key default gen_random_uuid(),
  phone text unique not null,
  name text not null,
  created_at timestamptz not null default now()
);

create table tournaments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references operators(id),
  name text not null,
  host_org text,
  date_start date,
  date_end date,
  rounds int not null default 2,
  venues jsonb not null default '[]',
  course_pars jsonb not null default '[]',
  tie_rule text,
  cap int not null default 120,
  fields jsonb not null default '{}',
  awards jsonb not null default '{}',
  status text not null default 'ready',
  created_at timestamptz not null default now()
);

create table staff (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  name text,
  phone text,
  duty text,
  can_score boolean not null default false,
  token uuid unique not null default gen_random_uuid(),
  link_opened_at timestamptz
);

create table players (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  name text not null,
  phone text not null,
  sex text,
  club text,
  region text,
  nick text,
  age int,
  status text not null default 'ok',
  group_no int,
  group_order int,
  created_at timestamptz not null default now(),
  unique (tournament_id, phone)
);

create table scores (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  player_id uuid not null references players(id) on delete cascade,
  hole_index int not null check (hole_index between 0 and 71),
  strokes int not null check (strokes between 1 and 15),
  entered_by uuid references staff(id),
  updated_at timestamptz not null default now(),
  unique (player_id, hole_index)
);

create table score_logs (
  id bigint generated always as identity primary key,
  tournament_id uuid,
  player_id uuid,
  hole_index int,
  old_strokes int,
  new_strokes int,
  reason text,
  entered_by uuid,
  created_at timestamptz not null default now()
);

-- RLS ---------------------------------------------------------------
alter table operators enable row level security;
alter table tournaments enable row level security;
alter table staff enable row level security;
alter table players enable row level security;
alter table scores enable row level security;
alter table score_logs enable row level security;

-- operators: 파일럿 단계는 전화번호+이름 매칭의 간이 로그인이라 서버 인증이 없다.
-- anon 키로 조회/가입/갱신이 가능해야 클라이언트(단일 HTML)가 동작하므로 임시로 전체 허용한다.
-- 한계: anon 키를 아는 누구나 전화번호 목록을 읽을 수 있음 — 문자 OTP 도입(3단계 이후) 시 좁힐 것.
create policy "operators_select_anon" on operators for select using (true);
create policy "operators_insert_anon" on operators for insert with check (true);
create policy "operators_update_anon" on operators for update using (true);

-- tournaments: 대회 리스트/전광판은 공개 페이지 → 읽기 공개, 개설은 로그인한 운영자가 바로 insert
create policy "tournaments_select_public" on tournaments for select using (true);
create policy "tournaments_insert_anon" on tournaments for insert with check (true);

-- staff: 아직 공개 조회가 필요 없음(전화번호·토큰 포함) — insert만 허용, select는 5단계 심판 토큰 검증(RPC)에서 다룸
create policy "staff_insert_anon" on staff for insert with check (true);

-- players / scores: 전광판·리더보드가 공개 페이지이므로 읽기는 지금부터 공개해 둔다.
-- 쓰기 정책은 3단계(참가 신청)·6단계(submit_score RPC)에서 추가한다.
create policy "players_select_public" on players for select using (true);
create policy "scores_select_public" on scores for select using (true);
