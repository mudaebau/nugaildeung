-- ============================================================================
--  파일럿 GO ① — 운영 DB 전면 정리
--  결정: ⓑ 데모 5건 보존, 나머지 110개 대회와 그 하위 행 전량 삭제
--  작성: Claude / 실행: 사용자(Supabase SQL Editor, service_role)
-- ============================================================================
--
-- ⚠️⚠️ 되돌릴 수 없습니다. ROLLBACK 파일이 없습니다. ⚠️⚠️
--   이 스크립트는 DELETE만 합니다. 커밋한 뒤에는 복구 수단이 없습니다
--   (마이그레이션과 달리 지워진 행을 되살리는 역연산이 존재하지 않습니다).
--   실행 전 Supabase 대시보드에서 백업/스냅샷을 한 번 떠 두시길 권합니다.
--
-- 실행 방법: 블록 A를 먼저 돌려 숫자를 눈으로 확인한 뒤, 블록 B를 돌립니다.
--   블록 B는 begin 으로 열려 있고 맨 끝 commit 은 주석 처리해 두었습니다.
--   확인 select 결과가 예상과 같을 때만 commit 줄의 주석을 풀어 실행하세요.
--   중간에 이상하면 rollback; 한 줄이면 전부 없던 일이 됩니다.
--
-- 삭제 순서(자식 → 부모): scores → plays → players → staff → stages → logs → tournaments
--
-- 보존 화이트리스트 5건 (2026-07-29 조회로 id 확정)
--   e0938c36-1f87-47ee-a1ed-eb7dec688fe0  솔터공원 7월 월례오픈            (open)
--   87fe6e1b-3cfc-4156-acc0-14468ae6ee12  하남시장배 생활체육 파크골프대회 (live)
--   c550b4a0-f21d-45be-b999-768d0a35aba2  청솔클럽 6월 정기전              (done)
--   b21d8640-4a13-43c6-ba70-6f1c9533eed0  제3회 경기도협회장배             (done)
--   5c150ad5-46c3-47e9-a687-b10562c38a16  한강은빛회 창립 5주년 친선전     (open)
--
-- 기존 스모크 잔여([TEST] 운영 스모크 · 010-0000-9999 · 010-0000-9998)와
-- 앞으로 만들 [TEST] 스모크 산출물은 전부 "보존 5건이 아닌 것"에 포함되므로
-- 이 화이트리스트 방식 하나로 같이 지워집니다. 별도 조건이 필요 없습니다.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 블록 A — 실행 전 확인 (읽기 전용, 아무것도 바꾸지 않습니다)
-- ────────────────────────────────────────────────────────────────────────────

-- A-1. 보존 5건이 정확히 5행으로 잡히는지. 5가 아니면 여기서 멈추세요.
select count(*) as 보존_대회수
from tournaments
where id in (
  'e0938c36-1f87-47ee-a1ed-eb7dec688fe0',
  '87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
  'c550b4a0-f21d-45be-b999-768d0a35aba2',
  'b21d8640-4a13-43c6-ba70-6f1c9533eed0',
  '5c150ad5-46c3-47e9-a687-b10562c38a16');

-- A-2. 삭제 예정 규모. 대회는 110이어야 합니다(전체 115 − 보존 5).
select
  (select count(*) from tournaments) as 전체_대회,
  (select count(*) from tournaments where id not in (
     'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
     'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
     '5c150ad5-46c3-47e9-a687-b10562c38a16')) as 삭제_대회,
  (select count(*) from scores  where tournament_id not in (
     'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
     'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
     '5c150ad5-46c3-47e9-a687-b10562c38a16')) as 삭제_홀기록,
  (select count(*) from plays   where tournament_id not in (
     'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
     'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
     '5c150ad5-46c3-47e9-a687-b10562c38a16')) as 삭제_총타기록,
  (select count(*) from players where tournament_id not in (
     'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
     'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
     '5c150ad5-46c3-47e9-a687-b10562c38a16')) as 삭제_참가자,
  (select count(*) from stages  where tournament_id not in (
     'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
     'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
     '5c150ad5-46c3-47e9-a687-b10562c38a16')) as 삭제_단계;

-- A-3. 보존 5건에 딸린 하위 행(이건 남아야 합니다). 0이어도 정상 — 데모 시드입니다.
select
  (select count(*) from players where tournament_id in (
     'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
     'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
     '5c150ad5-46c3-47e9-a687-b10562c38a16')) as 보존_참가자,
  (select count(*) from stages  where tournament_id in (
     'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
     'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
     '5c150ad5-46c3-47e9-a687-b10562c38a16')) as 보존_단계;

-- A-4. ⚠️ 운영자(operators) — 여기는 한 번 더 봐 주세요.
--   보존 5건은 owner_id 가 비어 있는 데모 시드라, "보존 대회의 소유자"라는 이유로
--   지켜지는 운영자가 한 명도 없습니다. 그래서 아래 블록 C(운영자 삭제)를 그냥 돌리면
--   operators 테이블이 통째로 비워집니다 — 사용자 본인 계정과, 혹시 있을 실제
--   이용자 계정까지 함께 사라집니다.
--   이 select 로 목록을 먼저 눈으로 보시고, 남길 사람을 정한 뒤에 블록 C를 쓰세요.
select id, name, phone, created_at
from operators
order by created_at;


-- ────────────────────────────────────────────────────────────────────────────
-- 블록 B — 대회 및 하위 행 삭제 (여기서부터 데이터가 바뀝니다)
--   A-2 숫자가 예상과 같을 때만 실행하세요.
-- ────────────────────────────────────────────────────────────────────────────
begin;

-- 자식부터. 화이트리스트에 없는 대회의 행을 전부 지웁니다.
delete from scores
 where tournament_id not in (
   'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
   'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
   '5c150ad5-46c3-47e9-a687-b10562c38a16');

delete from plays
 where tournament_id not in (
   'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
   'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
   '5c150ad5-46c3-47e9-a687-b10562c38a16');

delete from players
 where tournament_id not in (
   'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
   'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
   '5c150ad5-46c3-47e9-a687-b10562c38a16');

delete from staff
 where tournament_id not in (
   'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
   'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
   '5c150ad5-46c3-47e9-a687-b10562c38a16');

delete from stages
 where tournament_id not in (
   'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
   'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
   '5c150ad5-46c3-47e9-a687-b10562c38a16');

-- 로그 2종. 감사 기록이지만 대회 자체가 사라지므로 함께 정리합니다.
delete from score_logs
 where tournament_id not in (
   'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
   'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
   '5c150ad5-46c3-47e9-a687-b10562c38a16');

delete from tournament_edit_logs
 where tournament_id not in (
   'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
   'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
   '5c150ad5-46c3-47e9-a687-b10562c38a16');

-- 마지막으로 부모.
delete from tournaments
 where id not in (
   'e0938c36-1f87-47ee-a1ed-eb7dec688fe0','87fe6e1b-3cfc-4156-acc0-14468ae6ee12',
   'c550b4a0-f21d-45be-b999-768d0a35aba2','b21d8640-4a13-43c6-ba70-6f1c9533eed0',
   '5c150ad5-46c3-47e9-a687-b10562c38a16');

-- 커밋 전 확인. 대회 5, 그리고 하위 행은 보존 5건 것만 남아 있어야 합니다.
select
  (select count(*) from tournaments) as 남은_대회,
  (select count(*) from players)     as 남은_참가자,
  (select count(*) from stages)      as 남은_단계,
  (select count(*) from scores)      as 남은_홀기록,
  (select count(*) from plays)       as 남은_총타기록,
  (select count(*) from staff)       as 남은_심판;

select id, name, status from tournaments order by created_at;

-- 위 결과가 "남은_대회 = 5" 이고 목록이 보존 5건일 때만 아래 줄의 주석을 푸세요.
-- commit;
--
-- 이상하면 이 줄을 실행:
-- rollback;


-- ────────────────────────────────────────────────────────────────────────────
-- 블록 C — 운영자(operators) 정리  ※ 선택 실행, 기본은 실행하지 않음
-- ────────────────────────────────────────────────────────────────────────────
-- A-4 에서 설명한 이유로 여기는 화이트리스트를 자동으로 만들 수 없습니다.
-- 남길 계정(최소한 사용자 본인)의 전화번호를 직접 채운 뒤에만 쓰세요.
-- 빈 목록으로 실행하면 operators 가 전부 지워집니다.
--
-- begin;
-- delete from operators
--  where phone not in (
--    '010-0000-0000'   -- ← 남길 번호를 여기에. 사용자 본인 계정을 반드시 포함하세요.
--  );
-- select count(*) as 남은_운영자 from operators;
-- -- commit;
--
-- 참고: 대회를 먼저 지웠으므로 남는 operators 행은 아무 대회도 소유하지 않은
--   껍데기입니다. 로그인하면 빈 목록이 보일 뿐 동작에는 지장이 없습니다.
--   급하지 않다면 블록 C는 건너뛰고, 파일럿이 끝난 뒤 정리해도 됩니다.
