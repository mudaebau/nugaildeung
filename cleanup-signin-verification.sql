-- SIGNIN 차수 검증 중 생긴 테스트 데이터 정리

-- ① 테스트 대회(참가자·스태프 등은 tournament_id on delete cascade로 함께 정리됨)
delete from tournaments
where id = '221935dc-67ae-4821-96fe-e2b1f4ef793e'
  and name = '[TEST] SIGNIN검증대회';

-- ② 테스트 운영자 계정 — 010-9999-0555(정규화 버그 재현용, 0041 이전에 만들어져
--    표기 3종이 아직 별도 행), 010-9999-0777·010-9999-0888(정규화 정상 동작 검증용)
delete from operators
where phone in (
  '010-9999-0555','01099990555','010 9999 0555',
  '010-9999-0777','010-9999-0888'
);

-- 확인 (전부 0행이어야 함)
select id, name from tournaments where id = '221935dc-67ae-4821-96fe-e2b1f4ef793e';
select id, phone, name from operators
where phone in ('010-9999-0555','01099990555','010 9999 0555','010-9999-0777','010-9999-0888');
