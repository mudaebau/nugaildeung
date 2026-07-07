-- D2 후속 수정: plays 테이블이 0011에서 Realtime 발행 목록에 추가되지 않아
-- 전광판이 기간형 기록의 실시간 반영을 받지 못하던 문제를 고친다.

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='plays') then
    alter publication supabase_realtime add table plays;
  end if;
end $$;
