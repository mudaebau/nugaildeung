-- CH37-B 마무리: 단계별 일정 편집(허브 화면 7 v2 "단계 행 › 일정") — 순수 추가.
--
-- 왜 필요한가 — stages.date_start/date_end를 갱신하는 RPC가 하나도 없었다.
-- 0031에서 stages의 anon 직접 UPDATE 정책이 회수됐기 때문에, 콘솔에서 단계 일정을
-- 고칠 경로가 아예 없어 화면에서 읽기 전용으로 두고 있었다.
--
-- 기존 함수는 하나도 건드리지 않는다(update_stage_venues/update_stage_course/open_stage/
-- close_stage/advance_stage/confirm_advance 전부 무수정). 모바일(master)에는 단계 일정
-- 편집 UI가 없어 이 함수를 호출하지 않으므로 운영 영향 0.
-- 롤백: 0051_ch37_stage_dates_ROLLBACK.sql (drop function 1줄)

-- ── 실행 전 확인 ──
--   select proname from pg_proc where proname = 'update_stage_dates';   → 0행이어야 함

create or replace function update_stage_dates(
  t_id uuid, p_owner_secret uuid, stage_id uuid,
  p_date_start date, p_date_end date, p_who text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_kind text;
  v_name text;
  v_old_s date;
  v_old_e date;
  v_new_e date;
begin
  perform assert_owner(t_id, p_owner_secret);

  select kind, name, date_start, date_end
    into v_kind, v_name, v_old_s, v_old_e
    from stages where id = stage_id and tournament_id = t_id;
  if v_kind is null then
    raise exception '단계를 찾을 수 없습니다';
  end if;

  -- P31: 그 단계에 기록이 있으면 일정도 못 바꾼다(코스·컷과 같은 조건).
  if exists (select 1 from scores where stage_id = update_stage_dates.stage_id)
     or exists (select 1 from plays where stage_id = update_stage_dates.stage_id) then
    raise exception '이 단계에 기록이 있어 일정을 바꿀 수 없습니다';
  end if;

  if p_date_start is null then
    raise exception '시작일을 입력해 주세요';
  end if;

  if v_kind = 'period' then
    -- 기간형: 시작 ≤ 종료. 종료가 비면 시작일과 같은 날로 본다.
    v_new_e := coalesce(p_date_end, p_date_start);
    if v_new_e < p_date_start then
      raise exception '종료일이 시작일보다 앞설 수 없습니다';
    end if;
  else
    -- 지정일: 대회일 하나뿐이므로 종료일을 시작일과 같게 고정한다(달력에 하루로 보이도록).
    v_new_e := p_date_start;
  end if;

  update stages set date_start = p_date_start, date_end = v_new_e
    where id = stage_id and tournament_id = t_id;

  insert into tournament_edit_logs(tournament_id, who, what)
  values (t_id, coalesce(p_who, '운영자'),
          format('단계 일정 변경 — %s: %s → %s',
                 v_name,
                 coalesce(v_old_s::text, '미정') || case when v_kind = 'period'
                   then '~' || coalesce(v_old_e::text, '미정') else '' end,
                 p_date_start::text || case when v_kind = 'period'
                   then '~' || v_new_e::text else '' end));
end;
$$;
grant execute on function update_stage_dates(uuid, uuid, uuid, date, date, text) to anon;

-- ── 실행 후 확인 ──
--   select p.oid::regprocedure as 시그니처, n.nspname as 스키마,
--          has_function_privilege('anon', p.oid, 'EXECUTE') as anon_실행가능
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where p.proname = 'update_stage_dates';
--   → 1행: update_stage_dates(uuid,uuid,uuid,date,date,text) / public / true
--
--   notify pgrst, 'reload schema';   ← 실행 후 반드시(0050 때 캐시 때문에 한 번 막혔다)
