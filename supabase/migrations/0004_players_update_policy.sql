-- 4단계(조편성 저장): 조 배정(group_no/group_order) 갱신을 위해 players 테이블에 UPDATE 권한 추가.
-- 참가자 붙여넣기 등록/데모 등록도 이제 DB에 저장되므로 함께 동작한다.

create policy "players_update_anon" on players for update using (true);
