-- 0036_mask_phone_and_token.sql 롤백용 SQL.
-- 주의: 이 롤백은 "노출 차단 이전 상태"로 되돌리는 것 = 다시 취약해짐.
-- 회귀 테스트에서 막힌 기능이 있어 원인 파악이 급할 때만 임시로 쓰고,
-- 원인 해결 후 반드시 0036을 재적용할 것.

drop function if exists create_staff_batch(uuid, uuid, jsonb);
drop function if exists get_staff_owner(uuid, uuid);
drop function if exists get_staff_by_token(uuid);
drop view if exists players_public;

revoke select on players from anon;
grant select on players to anon; -- 전체 컬럼 재개방(원상복구)

revoke select on staff from anon;
grant select on staff to anon; -- 전체 컬럼 재개방(원상복구, token 포함)

drop function if exists mask_phone(text);

-- 롤백 후 확인:
--   select token, phone from staff limit 1;   -- 다시 보이면 롤백 성공(=취약 상태로 복귀)
--   select phone from players limit 1;        -- 다시 보이면 롤백 성공(=취약 상태로 복귀)
