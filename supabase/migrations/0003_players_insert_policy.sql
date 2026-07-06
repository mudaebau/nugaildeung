-- 3단계(참가 신청 저장): players 테이블에 anon 쓰기(INSERT) 권한 추가.
-- 읽기 정책은 0001_schema.sql에서 이미 공개로 열어둠.
-- 중복 전화번호 차단은 0001에서 만든 (tournament_id, phone) UNIQUE 제약이 그대로 담당한다.

create policy "players_insert_anon" on players for insert with check (true);
