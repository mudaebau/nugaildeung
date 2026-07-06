-- 5단계(심판 토큰 링크): ?j={token} 접속 시 staff를 토큰으로 조회하고 link_opened_at을 기록해야 하므로
-- staff 테이블에 SELECT/UPDATE 권한을 추가한다.
-- 한계: anon 키로 staff 전체를 조회할 수 있어 전화번호가 노출된다 — token은 uuid라 추측이 사실상 불가능하지만,
-- 엄밀한 보호가 필요해지면 이후 RPC(SECURITY DEFINER)로 좁힐 것.

create policy "staff_select_anon" on staff for select using (true);
create policy "staff_update_anon" on staff for update using (true);
