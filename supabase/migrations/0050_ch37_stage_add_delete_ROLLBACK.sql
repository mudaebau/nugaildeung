-- ROLLBACK of 0050 — 순수 추가였으므로 함수 제거로 원상복구.
-- 기존 함수(create_stages/open_stage/close_stage/advance_stage/confirm_advance 등)는
-- 0050에서 건드리지 않았으므로 되돌릴 것이 없다. 데이터도 변형하지 않았다
-- (add_stage로 만든 단계가 남아 있다면 그건 운영자가 만든 실데이터이므로 자동 삭제하지 않는다).
drop function if exists add_stage(uuid, uuid, jsonb);
drop function if exists delete_last_stage(uuid, uuid, uuid, text);
