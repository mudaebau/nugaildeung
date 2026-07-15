-- CH28-B2: 운영진 탭 완성 — 심판 추가/삭제/재발급.
-- 배경: 위저드에 심판 등록 화면이 없는데 createTournament()가 하드코딩된 데모 4명
-- (박민지 등, 가짜 번호)을 매번 실제 심판으로 자동 삽입했고, 등록 후 고칠 방법도
-- 전혀 없었다(OP-070~072 미구현). 클라이언트에서 자동 삽입을 제거하는 것과 짝을
-- 이루는 서버 측 변경 — 추가는 기존 create_staff_batch(HOTFIX-P0) 재사용, 삭제·
-- 재발급만 신규.
--
-- 하지 말 것(재사용 원칙): assert_owner/create_staff_batch/get_staff_owner는 그대로
-- 재사용. delete_player의 "기록 있으면 삭제 대신 대체 처리" 패턴을 그대로 따른다.

-- ── 삭제 ── 점수 입력 이력이 없으면 완전 삭제. 있으면(scores/plays.entered_by
-- FK가 참조 중이라 DELETE가 막힘) 완전 삭제 대신 can_score=false + 토큰 재발급으로
-- "토큰 즉시 무효"만 확실히 보장 — 정정 이력·score_logs 무결성은 그대로 보존.
create or replace function delete_staff(t_id uuid, p_staff_id uuid, p_owner_secret uuid)
returns text
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_has_history boolean;
begin
  perform assert_owner(t_id, p_owner_secret);
  select exists(select 1 from scores s where s.entered_by = p_staff_id)
      or exists(select 1 from plays pl where pl.entered_by = p_staff_id)
  into v_has_history;
  if v_has_history then
    update staff set can_score = false, token = gen_random_uuid()
    where id = p_staff_id and tournament_id = t_id;
    return 'deactivated';
  else
    delete from staff where id = p_staff_id and tournament_id = t_id;
    return 'deleted';
  end if;
end;
$$;
grant execute on function delete_staff(uuid, uuid, uuid) to anon;

-- ── 재발급 ── 새 토큰으로 교체(구 토큰은 그 순간 어떤 조회에도 안 걸려 즉시 무효),
-- link_opened_at도 초기화해 "미접속"으로 되돌아가게 한다(새 링크를 아직 안 열었으므로).
create or replace function reissue_staff_token(t_id uuid, p_staff_id uuid, p_owner_secret uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_token uuid;
begin
  perform assert_owner(t_id, p_owner_secret);
  update staff set token = gen_random_uuid(), link_opened_at = null
  where id = p_staff_id and tournament_id = t_id
  returning token into v_token;
  return v_token;
end;
$$;
grant execute on function reissue_staff_token(uuid, uuid, uuid) to anon;

-- ══════════════════════════════════════════════════════════════════════════
-- 검증 쿼리 안내(관리자 세션 postgres는 RLS와 무관하지만 이 함수들은 assert_owner로
-- 자체 검증하므로 SQL 에디터에서 바로 호출해도 됨 — 실제 owner_secret 필요)
--
-- 1) 삭제(이력 없음) — 'deleted' 반환 + 행 사라짐 확인:
--   select delete_staff('<t_id>', '<staff_id, 이력없음>', '<owner_secret>');
--   select count(*) from staff where id = '<staff_id>'; -- 0
--
-- 2) 삭제(이력 있음) — 'deactivated' 반환 + can_score=false·토큰 변경 확인:
--   select delete_staff('<t_id>', '<staff_id, 이력있음>', '<owner_secret>');
--   select can_score, token from staff where id = '<staff_id>';
--
-- 3) 재발급 — 새 토큰 반환, 구 토큰으로 get_staff_by_token 조회 시 빈 결과:
--   select reissue_staff_token('<t_id>', '<staff_id>', '<owner_secret>');
--   select * from get_staff_by_token('<구 토큰>'); -- 0행
--   select * from get_staff_by_token('<새 토큰>'); -- 1행
--
-- 4) 잘못된 owner_secret으로 시도 시 거부 확인:
--   select delete_staff('<t_id>', '<staff_id>', '00000000-0000-0000-0000-000000000000');
--   -- '이 대회의 운영자만 할 수 있는 작업입니다' 예외
-- ══════════════════════════════════════════════════════════════════════════
