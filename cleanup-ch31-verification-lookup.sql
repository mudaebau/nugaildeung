-- CH31 실기기 검증 중 생성된 테스트 대회 조회 — 삭제 대상 확정용
-- 최근 생성된 [TEST] 접두사 대회를 최신순으로 나열합니다.
-- 결과를 보고 삭제할 id를 골라주시면 최종 정리 SQL을 만들어 드립니다.
select id, name, status, owner_id, created_at,
  (select count(*) from players p where p.tournament_id = t.id) as player_count
from tournaments t
where name like '[TEST]%'
order by created_at desc
limit 30;
