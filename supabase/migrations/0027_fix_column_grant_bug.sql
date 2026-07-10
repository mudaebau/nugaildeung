-- 0024/0026에서 시도한 컬럼 단위 revoke(access_code, operators.secret)가
-- 실제로는 적용되지 않는 게 라이브 검증 중 발견됐다.
--
-- 원인: 이 프로젝트는 부트스트랩 시점에 anon에 테이블 단위 SELECT(예: grant select on
-- tournaments to anon, 또는 grant all)가 이미 부여돼 있다. 컬럼 단위 revoke
-- (revoke select (col) on table from anon)는 그 자체로는 새로운 컬럼 단위 권한 항목을
-- "차감"하려는 시도지만, 이미 존재하는 테이블 단위 SELECT 권한이 모든 컬럼에 대한 접근을
-- 포함하고 있어서 컬럼 단위 revoke만으로는 실질적으로 아무 효과가 없다
-- (information_schema.column_privileges로 확인해보면 anon이 access_code에 대해
-- 여전히 SELECT를 갖고 있음이 드러남).
--
-- 올바른 방법: 테이블 단위 SELECT를 완전히 회수한 뒤, 노출해도 되는 컬럼만
-- 컬럼 단위로 다시 GRANT한다.

-- tournaments: access_code만 제외하고 나머지 컬럼을 다시 연다.
-- (INSERT 정책과 UPDATE/DELETE 미개방 상태는 그대로 유지 — 이번엔 SELECT만 손댄다.)
revoke select on tournaments from anon;
grant select (
  id, owner_id, name, host_org, date_start, date_end, rounds, venues, course_pars,
  tie_rule, cap, fields, awards, status, created_at, type, visibility, notice_extra, reg_closed
) on tournaments to anon;

-- operators: 클라이언트는 이제 operator_signup RPC(security definer, 권한 우회)로만
-- 접근하고 직접 select하는 곳이 없으므로, anon의 테이블 단위 SELECT를 전부 회수하고
-- 컬럼 단위로도 다시 열어주지 않는다(완전 비공개).
revoke select on operators from anon;
