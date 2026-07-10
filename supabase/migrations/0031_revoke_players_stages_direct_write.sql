-- 차수21 완료: players/stages에 대한 anon 직접 insert/update 정책을 전부 회수한다.
-- 0028~0030에서 만든 RPC(전부 assert_owner 검증 또는 apply_to_tournament의 자체 검증을 거침)로
-- 클라이언트를 완전히 전환한 뒤에만 이 마이그레이션을 실행할 것 — 먼저 실행하면
-- 참가자 추가/수정/조편성/단계 관리가 즉시 전부 깨진다.
--
-- select 정책(players_select_public, stages_select_public)은 그대로 둔다 —
-- 전광판·요강 등 공개 읽기는 이번 범위가 아니다.

drop policy if exists "players_insert_anon" on players;
drop policy if exists "players_update_anon" on players;
drop policy if exists "stages_insert_anon" on stages;
drop policy if exists "stages_update_anon" on stages;
