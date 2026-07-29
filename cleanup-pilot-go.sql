-- ============================================================================
--  파일럿 GO ① — 운영 DB 전면 정리
--  결정: ⓑ 데모 5건 보존, 나머지 대회와 그 하위 행 전량 삭제
--  작성: Claude / 실행: 사용자(Supabase SQL Editor, service_role)
-- ============================================================================
--
-- ⚠️⚠️ 되돌릴 수 없습니다. ROLLBACK 파일이 없습니다. ⚠️⚠️
--   이 스크립트는 DELETE만 합니다. 성공하면 지워진 행을 되살리는 역연산이
--   존재하지 않습니다. 실행 전 Supabase 대시보드에서 백업/스냅샷을 떠 두세요.
--
-- ── 이 파일은 2회 실행이 전제입니다 (정리 먼저 순서를 택했으므로) ──
--   1단계  블록 B 1차 실행       → 기존 110개 대회 + 하위 행 삭제
--   2단계  [TEST] 스모크 4종     → 콘솔 개설 · 폰 신청 · 전광판 · 모바일 라임
--                                  (운영 DB에 [TEST] 대회·참가자가 새로 생깁니다)
--   3단계  블록 B 2차 실행       → 스모크 산출물 삭제
--   4단계  파일럿 실개설         → 깨끗한 상태에서 시작
--
--   블록 B는 "보존 5건이 아닌 것을 전부 지운다"는 화이트리스트 방식이라
--   몇 번을 돌려도 결과가 같습니다(멱등). 그래서 2차 실행의 기대치도
--   1차와 똑같이 **남은 대회 = 5** 입니다. 스모크가 몇 건을 만들었든
--   2차 실행 후에는 보존 5건만 남습니다.
--
-- ── 안전장치 ──
--   블록 B의 삭제 전체는 DO $$ ... $$ 하나로 묶여 있고, 마지막에 남은 대회 수를
--   세서 5가 아니면 raise exception 으로 **DB가 스스로 전부 롤백**합니다.
--   Supabase SQL Editor 는 Run 단위로 자동 커밋되므로 "확인하고 주석 풀기"
--   방식은 성립하지 않습니다(확인하는 시점엔 이미 커밋된 뒤입니다).
--   사람 눈이 아니라 DB가 안전장치를 쥐게 했습니다.
--
-- ── 삭제 순서와 그 근거 (0001_schema.sql 의 FK 실제 확인) ──
--   scores.entered_by  → staff(id)    : cascade 아님 → scores 를 staff 보다 먼저
--   scores.stage_id    → stages(id)   : cascade 아님 → scores 를 stages 보다 먼저
--   plays.uploaded_by  → staff(id)    : cascade 아님 → plays  를 staff 보다 먼저
--   tournaments.owner_id → operators  : cascade 아님 → tournaments 를 operators 보다 먼저
--   score_logs         : FK 없음(tournament_id·player_id·entered_by 모두 bare uuid)
--   tournament_edit_logs : tournament_id 만 있고 FK 없음
--   → 그래서 로그 2종은 순서 제약이 없습니다. scores 를 참조하지 않으므로
--     앞으로 옮길 필요도 없습니다. 아래 순서가 모든 FK를 만족합니다:
--     scores → plays → players → staff → stages → 로그 2종 → tournaments
--
-- 보존 화이트리스트 5건 (2026-07-29 조회로 id 확정, 5/5 일치)
--   e0938c36-1f87-47ee-a1ed-eb7dec688fe0  솔터공원 7월 월례오픈            (open)
--   87fe6e1b-3cfc-4156-acc0-14468ae6ee12  하남시장배 생활체육 파크골프대회 (live)
--   c550b4a0-f21d-45be-b999-768d0a35aba2  청솔클럽 6월 정기전              (done)
--   b21d8640-4a13-43c6-ba70-6f1c9533eed0  제3회 경기도협회장배             (done)
--   5c150ad5-46c3-47e9-a687-b10562c38a16  한강은빛회 창립 5주년 친선전     (open)
--
-- 기존 스모크 잔여(010-0000-9999 · 대회 107aab9d… · 참가자 010-0000-9998)와
-- 앞으로 만들 [TEST] 산출물은 전부 "보존 5건이 아닌 것"이라 같이 지워집니다.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 블록 A — 실행 전 확인 (읽기 전용, 아무것도 바꾸지 않습니다)
--   1차·2차 실행 모두 이걸 먼저 돌려 숫자를 보고 들어가세요.
-- ────────────────────────────────────────────────────────────────────────────

-- A-1. 보존 5건이 정확히 5행인지. 5가 아니면 여기서 멈추세요.
select count(*) as 보존_대회수
from tournaments
where id = any (array[
  'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
  'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
  '5c150ad5-46c3-47e9-a687-b10562c38a16']::uuid[]);

-- A-2. 삭제 예정 규모(1차 실행 시 삭제_대회 = 110 기대. 2차는 스모크가 만든 수).
with keep as (select array[
  'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
  'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
  '5c150ad5-46c3-47e9-a687-b10562c38a16']::uuid[] as ids)
select
  (select count(*) from tournaments)                                              as 전체_대회,
  (select count(*) from tournaments t, keep k where t.id  <> all (k.ids))          as 삭제_대회,
  (select count(*) from scores  s, keep k where s.tournament_id <> all (k.ids))    as 삭제_홀기록,
  (select count(*) from plays   p, keep k where p.tournament_id <> all (k.ids))    as 삭제_총타기록,
  (select count(*) from players p, keep k where p.tournament_id <> all (k.ids))    as 삭제_참가자,
  (select count(*) from staff   f, keep k where f.tournament_id <> all (k.ids))    as 삭제_심판,
  (select count(*) from stages  g, keep k where g.tournament_id <> all (k.ids))    as 삭제_단계;

-- A-3. 보존 5건에 딸린 하위 행(이건 남아야 합니다). 0이어도 정상 — 데모 시드입니다.
with keep as (select array[
  'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
  'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
  '5c150ad5-46c3-47e9-a687-b10562c38a16']::uuid[] as ids)
select
  (select count(*) from players p, keep k where p.tournament_id = any (k.ids)) as 보존_참가자,
  (select count(*) from stages  g, keep k where g.tournament_id = any (k.ids)) as 보존_단계;

-- A-4. 운영자 목록 — 블록 C를 쓸 때 참고용. 지금은 건드리지 않습니다.
select id, name, phone, created_at from operators order by created_at;


-- ────────────────────────────────────────────────────────────────────────────
-- 블록 B — 삭제 (Run 한 번에 전부 실행됩니다. 통째로 복사해서 돌리세요)
--   끝에서 남은 대회 수가 5가 아니면 예외를 던져 전부 자동 롤백합니다.
--   1차·2차 실행 모두 이 블록을 그대로 씁니다.
-- ────────────────────────────────────────────────────────────────────────────
do $$
declare
  keep uuid[] := array[
    'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
    'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
    '5c150ad5-46c3-47e9-a687-b10562c38a16']::uuid[];
  remain int;
  n_before int;
begin
  select count(*) into n_before from tournaments;

  -- 자식부터. FK 근거는 파일 머리 주석 참조.
  delete from scores  where tournament_id <> all (keep);
  delete from plays   where tournament_id <> all (keep);
  delete from players where tournament_id <> all (keep);
  delete from staff   where tournament_id <> all (keep);
  delete from stages  where tournament_id <> all (keep);

  -- 로그 2종(FK 없음). tournament_id 가 NULL 인 고아 로그는 건드리지 않습니다 —
  -- 어느 대회 것인지 판정할 근거가 없어 지울지 남길지를 정할 수 없기 때문입니다.
  delete from score_logs           where tournament_id is not null and tournament_id <> all (keep);
  delete from tournament_edit_logs where tournament_id is not null and tournament_id <> all (keep);

  -- 마지막으로 부모.
  delete from tournaments where id <> all (keep);

  -- ── 자동 안전장치 ──
  select count(*) into remain from tournaments;
  if remain <> 5 then
    raise exception '남은 대회 %건 — 기대 5건, 롤백', remain;
  end if;

  raise notice '정리 완료 — 대회 %건 → %건 (보존 5건)', n_before, remain;
end $$;

-- 블록 B 실행 후 확인 (별도 Run). 대회 5행, 목록은 보존 5건이어야 합니다.
select
  (select count(*) from tournaments) as 남은_대회,
  (select count(*) from players)     as 남은_참가자,
  (select count(*) from stages)      as 남은_단계,
  (select count(*) from scores)      as 남은_홀기록,
  (select count(*) from plays)       as 남은_총타기록,
  (select count(*) from staff)       as 남은_심판;

select id, name, status from tournaments order by created_at;


-- ────────────────────────────────────────────────────────────────────────────
-- 블록 C — 운영자(operators) 정리  ※ 파일럿 이후로 미룸. 지금 실행하지 않습니다.
-- ────────────────────────────────────────────────────────────────────────────
-- 보존 5건은 owner_id 가 비어 있는 데모 시드라, "보존 대회의 소유자"라는 이유로
-- 지켜지는 운영자가 한 명도 없습니다. 자동으로 돌리면 operators 가 통째로 비워져
-- 사용자 본인 계정까지 사라집니다. 남길 번호를 직접 채운 뒤에만 쓰세요.
--
-- do $$
-- declare
--   keep_phone text[] := array['010-0000-0000'];  -- ← 본인 계정을 반드시 포함
--   remain int;
-- begin
--   delete from operators where phone <> all (keep_phone);
--   select count(*) into remain from operators;
--   if remain < 1 then
--     raise exception '운영자가 0명이 됨 — 롤백';
--   end if;
--   raise notice '운영자 %명 남음', remain;
-- end $$;
--
-- 참고: 대회를 먼저 지웠으므로 남는 operators 행은 아무 대회도 소유하지 않은
--   껍데기입니다. 로그인하면 빈 목록이 보일 뿐 동작에는 지장이 없습니다.
