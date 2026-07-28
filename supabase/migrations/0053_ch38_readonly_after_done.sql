-- CH38 ⑤: 종료(status='done') 후 읽기 전용 — 0047(scores_locked) 트리거와 같은 문법.
--
-- 무엇을 막나: done 대회의 players · scores · plays · stages에 대한 INSERT/UPDATE.
-- 무엇을 안 막나:
--   · DELETE — 파일럿 후 [TEST] 정리 SQL이 막히면 안 된다(승인된 결정 #1).
--   · tournaments — finalize_tournament가 status='done'을 쓰는 순간 자기 자신이 걸린다.
--     종료 후 요강 편집 차단은 아래 ②에서 RPC 가드로 따로 처리한다(승인된 결정 #2).
--   · tournament_edit_logs / score_logs — 종료 이후에도 감사 기록은 남아야 한다(결정 #3).
--   · 멱등성: finalize_tournament는 tournaments만 쓰므로 트리거와 무관, 재실행해도 안전(결정 #4).
--
-- ── 5-1 의존성 문답(운영 모바일 master 기준, 코드로 확인함) ──
--   이미 done 가드가 있던 경로: 심판 토큰 입력(0025) · 단계 수명주기(0029/0046) ·
--     기록 정정(0034/0043) · 운영자 점수(0043/0044) · 단계 추가삭제(0050).
--   가드가 없던 경로: players CRUD(0028) · confirm_stage_roster(0032) · 요강 편집(0021).
--   모바일은 종료 대회에서 이 경로들을 호출하지 않는다 — computeTodoBadge는 done이면
--   즉시 null로 빠지고(master index.html:2925), 관리 화면은 finished면 컨트롤을 닫는다
--   (master index.html:2398-2458). 따라서 이 트리거로 운영이 깨지지 않는다.
--
-- ⚠️ 비가역성(승인됨, 파일럿 후 [종료 취소] UI는 백로그):
--   트리거 적용 후 종료는 UI로 되돌릴 수 없다. 실수로 종료 확정한 경우 아래 한 줄로 복구한다
--   (tournaments는 트리거 대상이 아니므로 이 UPDATE는 막히지 않는다):
--
--       update tournaments set status = 'live' where id = '<대회 id>';
--
--   되돌린 뒤에는 해당 대회의 players/scores/plays/stages 수정이 다시 열린다.
--
-- 롤백: 0053_ch38_readonly_after_done_ROLLBACK.sql

-- ── 실행 전 확인 ──
--   select tgname from pg_trigger where tgname like 'trg_readonly_done_%';  → 0행
--   select proname from pg_proc where proname='assert_tournament_not_done'; → 0행

/* ① done 대회 쓰기 차단 트리거 */
create or replace function assert_tournament_not_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
begin
  select status into v_status from tournaments where id = NEW.tournament_id;
  if v_status = 'done' then
    raise exception '종료된 대회는 수정할 수 없습니다 — 기록 보관 중입니다';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_readonly_done_players on players;
create trigger trg_readonly_done_players
  before insert or update on players
  for each row execute function assert_tournament_not_done();

drop trigger if exists trg_readonly_done_scores on scores;
create trigger trg_readonly_done_scores
  before insert or update on scores
  for each row execute function assert_tournament_not_done();

drop trigger if exists trg_readonly_done_plays on plays;
create trigger trg_readonly_done_plays
  before insert or update on plays
  for each row execute function assert_tournament_not_done();

drop trigger if exists trg_readonly_done_stages on stages;
create trigger trg_readonly_done_stages
  before insert or update on stages
  for each row execute function assert_tournament_not_done();

/* ② 요강 편집 RPC에 done 가드 추가 (승인된 예외 — 기존 함수 변경)
   tournaments는 트리거 대상이 아니므로 여기서 막지 않으면 종료 후에도 요강이 수정된다.
   본문은 기존과 동일하고 맨 앞 가드 한 줄만 추가한다. 시그니처 불변(= replace 성립). */
create or replace function update_tournament_free_info(
  t_id uuid, p_name text, p_host_org text, p_awards jsonb,
  p_prize_total text, p_prizes jsonb, p_contact text, p_fee text, p_rules text,
  p_owner_secret uuid, p_who text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  if exists (select 1 from tournaments where id = t_id and status = 'done') then
    raise exception '종료된 대회는 수정할 수 없습니다 — 기록 보관 중입니다';
  end if;
  update tournaments set
    name = p_name, host_org = p_host_org, awards = p_awards,
    notice_extra = coalesce(notice_extra,'{}'::jsonb) || jsonb_build_object(
      'prize_total', p_prize_total, 'prizes', p_prizes,
      'contact', p_contact, 'fee', p_fee, 'rules', p_rules)
  where id = t_id;
  insert into tournament_edit_logs(tournament_id, who, what)
    values (t_id, p_who, '기본 정보 수정 (대회명·주최·시상·요강정보)');
end;
$$;

create or replace function update_tournament_warned_info(
  t_id uuid, p_date_start date, p_date_end date, p_cap int,
  p_eligibility jsonb, p_visibility text, p_access_code text, p_owner_secret uuid,
  p_who text, p_what text, p_cap_unlimited boolean default false, p_fields jsonb default null,
  p_venue_place text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  if exists (select 1 from tournaments where id = t_id and status = 'done') then
    raise exception '종료된 대회는 수정할 수 없습니다 — 기록 보관 중입니다';
  end if;
  update tournaments set
    date_start = p_date_start, date_end = p_date_end, cap = p_cap, cap_unlimited = p_cap_unlimited,
    visibility = p_visibility,
    access_code = case when p_visibility = 'private' then p_access_code else null end,
    notice_extra = coalesce(notice_extra,'{}'::jsonb)
      || jsonb_build_object('eligibility', p_eligibility)
      || case when p_venue_place is not null then jsonb_build_object('venue_place', p_venue_place) else '{}'::jsonb end,
    fields = coalesce(p_fields, fields)
  where id = t_id;
  insert into tournament_edit_logs(tournament_id, who, what) values (t_id, p_who, p_what);
end;
$$;

-- ── 실행 후 확인 ──
--   select tgname, tgrelid::regclass as 테이블 from pg_trigger
--   where tgname like 'trg_readonly_done_%' order by 1;
--   → 4행: players / plays / scores / stages
--
--   select proname from pg_proc where proname='assert_tournament_not_done';  → 1행
--
--   동작 확인(종료된 대회 하나를 골라 — 반드시 [TEST] 대회로):
--     update players set name = name where tournament_id = '<done 대회 id>';
--     → ERROR: 종료된 대회는 수정할 수 없습니다 — 기록 보관 중입니다
--     delete는 막히지 않는다(정리 SQL 보존).
--
--   notify pgrst, 'reload schema';   ← RPC 2종을 replace했으므로 반드시 실행
