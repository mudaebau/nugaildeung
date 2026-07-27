-- CH28 전수검증 1차 + CH29 버그수정 검증 중 생긴 leftover 정리
-- T1~T7(전수검증 1차 본체, 아래 표) 라이브 7건은 2차 실기기 검증용으로 유지 — 삭제 대상 아님
--   T1 64dd3f8b-eb89-49cd-8815-d12ca349db58 / T2 015eb894-97bc-4394-b737-a12e661a9927
--   T3 8d1af43f-453b-44d8-ad7a-2cbb702b2472 / T4 642bda11-e4f8-424f-8978-6f6272516c35
--   T5 2a89f3df-4b66-49af-8f54-ccc84e092e7b / T6 163c14f1-ae39-4921-bb54-fdeb9344f26a
--   T7 42b13edd-64b3-4687-94af-e361900fc8b3

-- ① T3 생성 중 타임아웃으로 남은 빈 중복 대회(참가자 0명, 미사용)
delete from tournaments
where id = '858570c1-84a6-4050-ada2-bce1718d1700'
  and name = '[TEST] T3 비공개3단계';

-- ② CH25 이전 구버전 위저드로 만든 옛 테스트 대회(2026-07-10, 검증 범위 밖)
delete from tournaments
where id = 'aa3a4968-2f6e-4e06-879b-7eb7102cd272'
  and name = '[TEST] T1 파일럿대표형';

-- ③ CH29 수정①(단계 상태 동기화) 검증용 임시 대회 — 기간형→라운드형 2단계, 참가자 3명
delete from tournaments
where name = '[TEST] CH29 전환동기화';

-- ④ CH29 수정③(정원 하한 8→4) 검증용 임시 대회
delete from tournaments
where name = '[TEST] OP020검증';

-- 확인 (전부 0행이어야 함)
select id, name from tournaments
where id in ('858570c1-84a6-4050-ada2-bce1718d1700','aa3a4968-2f6e-4e06-879b-7eb7102cd272')
   or name in ('[TEST] CH29 전환동기화','[TEST] OP020검증');
