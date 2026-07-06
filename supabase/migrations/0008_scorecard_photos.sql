-- Phase C: 스코어카드 사진 입력
-- 현재 앱에는 stages/plays가 없으므로(D1/D2는 별도 단계), 기존 홀별 점수 입력(scores)과
-- "병행"하는 조·코스 단위 증빙 사진을 별도 테이블로 저장한다.
-- 사진은 판독(OCR)해서 점수에 자동 반영하지 않는다 — 어디까지나 심판 입력의 보조 증빙이다.

create table scorecard_photos (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  group_no int not null,
  course_no int not null,
  photo_url text not null,
  uploaded_by uuid references staff(id),
  created_at timestamptz not null default now()
);

alter table scorecard_photos enable row level security;

-- 전광판/운영자가 볼 수 있도록 읽기는 공개. 업로드는 심판 화면에서 anon 키로 바로 수행한다.
create policy "scorecard_photos_select_public" on scorecard_photos for select using (true);
create policy "scorecard_photos_insert_anon" on scorecard_photos for insert with check (true);

-- Storage: 스코어카드 사진 버킷 (공개 읽기)
insert into storage.buckets (id, name, public)
values ('scorecards', 'scorecards', true)
on conflict (id) do nothing;

create policy "scorecards_bucket_select_public" on storage.objects
  for select using (bucket_id = 'scorecards');
create policy "scorecards_bucket_insert_anon" on storage.objects
  for insert with check (bucket_id = 'scorecards');
