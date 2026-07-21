-- 0041 롤백 — SIGNIN 전화번호 정규화 + 재방문 세션 확인 RPC 제거.
-- 클라이언트가 이 RPC들(특히 새 반환 컬럼 is_new/active_count, operator_session_check)을
-- 이미 쓰도록 바뀌었으므로, 롤백 시 클라이언트도 함께 이전 커밋으로 되돌려야 한다.

drop function if exists operator_session_check(text, uuid);

drop function if exists operator_signup(text, text);
create or replace function operator_signup(p_phone text, p_name text)
returns table(id uuid, name text, secret uuid)
language plpgsql security definer set search_path = public as $$
begin
  return query
    insert into operators as o (phone, name) values (p_phone, p_name)
    on conflict (phone) do update set name = excluded.name
    returning o.id, o.name, o.secret;
end;
$$;
grant execute on function operator_signup(text, text) to anon;

drop function if exists normalize_phone(text);
