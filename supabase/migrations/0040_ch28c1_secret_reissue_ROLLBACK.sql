-- 0040 롤백 — 운영자 secret 재발급 RPC 제거.
drop function if exists reissue_operator_secret(text);
