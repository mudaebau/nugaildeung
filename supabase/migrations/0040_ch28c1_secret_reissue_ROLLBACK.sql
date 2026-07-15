-- 0040 롤백 — 운영자 secret 재발급 RPC·쿨다운 컬럼 제거.
drop function if exists reissue_operator_secret(text);
alter table operators drop column if exists secret_reissued_at;
