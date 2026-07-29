-- CH33-B 실기기 검증 중 생성된 테스트 대회 조회 — 삭제 대상 확정용.
-- 콘솔에서 만든 [TEST] 접두사 대회를 최신순으로 나열합니다(조회만 — 삭제 아님).
-- 결과의 id를 확인하시면 최종 삭제 SQL을 만들어 드립니다.
-- 삭제는 tournaments 한 건이면 players·stages·scores·plays 모두 cascade 됩니다.
-- (참고: 0047 트리거는 INSERT·UPDATE만 막으므로 잠금 상태여도 대회 삭제 cascade는 정상 동작합니다.)
select t.id, t.name, t.status, t.created_at,
  (select count(*) from players p where p.tournament_id = t.id) as players,
  (select count(*) from stages s where s.tournament_id = t.id and s.scores_locked) as locked_stages
from tournaments t
where t.name like '[TEST]%'
order by t.created_at desc
limit 30;
