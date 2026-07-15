-- 0039 롤백 — 심판 삭제/재발급 RPC 제거.
-- 클라이언트가 이 RPC들을 이미 호출하도록 바뀌었으므로, 롤백 시 클라이언트도
-- 함께 이전 커밋으로 되돌려야 한다(이 SQL만 되돌리면 UI의 삭제/재발급 버튼이
-- PGRST202로 실패한다).

drop function if exists delete_staff(uuid, uuid, uuid);
drop function if exists reissue_staff_token(uuid, uuid, uuid);
