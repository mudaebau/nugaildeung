-- CH30-A 검증 중 생긴 테스트 대회 3건 정리
delete from tournaments
where id in (
  'dd319ce4-78bd-4fe0-9c86-c3b455577d7b', -- [TEST] CH30 T2위저드
  '49acc091-cdab-4a76-8380-9be0795ce7c5', -- [TEST] CH30 T7위저드
  '80f6b342-9b2c-4097-9438-1e9c97263c10'  -- [TEST] CH30 단판
)
and name like '[TEST] CH30%';

-- 확인 (0행이어야 함)
select id, name from tournaments
where id in (
  'dd319ce4-78bd-4fe0-9c86-c3b455577d7b',
  '49acc091-cdab-4a76-8380-9be0795ce7c5',
  '80f6b342-9b2c-4097-9438-1e9c97263c10'
);
