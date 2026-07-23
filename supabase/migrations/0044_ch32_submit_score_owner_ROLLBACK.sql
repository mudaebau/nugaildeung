-- 0044_ch32_submit_score_owner.sql 롤백

drop function if exists submit_score_owner(uuid, uuid, uuid, int, int, text);
