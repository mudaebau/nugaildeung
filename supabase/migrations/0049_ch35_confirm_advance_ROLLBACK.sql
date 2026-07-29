-- ROLLBACK of 0049 — 순수 추가였으므로 함수 제거로 원상복구(advance_stage는 애초에 무수정).
drop function if exists confirm_advance(uuid,uuid,uuid,uuid,uuid[]);
