-- ROLLBACK of 0047_ch33_scores_locked.sql — 순수 추가였으므로 전부 제거하면 원상 복구.
drop trigger if exists trg_scores_locked on scores;
drop trigger if exists trg_plays_locked on plays;
drop function if exists ch33_block_locked_scores();
drop function if exists lock_stage_scores(uuid,uuid,uuid);
drop function if exists unlock_stage_scores(uuid,uuid,uuid);
alter table stages drop column if exists scores_locked;
