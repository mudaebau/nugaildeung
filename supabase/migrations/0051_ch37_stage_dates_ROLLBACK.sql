-- ROLLBACK of 0051 — 순수 추가였으므로 함수 제거로 원상복구.
-- 기존 함수는 0051에서 건드리지 않았고 데이터도 변형하지 않았다
-- (이미 바뀐 단계 일정은 운영자가 의도한 실데이터이므로 되돌리지 않는다).
--
-- ⚠ 이 파일은 "되돌릴 때만" 실행한다. 본체(0051_ch37_stage_dates.sql)를 실행한 직후
--    정리 차원에서 이 파일을 돌리면 함수가 사라져 콘솔에서 일정 저장이 실패한다.
drop function if exists update_stage_dates(uuid, uuid, uuid, date, date, text);
