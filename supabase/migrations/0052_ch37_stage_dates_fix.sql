-- 0051 버그 수정 — update_stage_dates가 P31 검사에서 즉시 실패했다.
--
-- 증상: 콘솔에서 단계 일정을 저장하면 'column reference "stage_id" is ambiguous'.
-- 원인: P31 검사의 where 절 왼쪽 stage_id를 한정하지 않았다.
--   if exists (select 1 from scores where stage_id = update_stage_dates.stage_id)
--                                         ^^^^^^^^ scores.stage_id(컬럼)인지
--                                                  함수 파라미터 stage_id인지 모호
-- 오른쪽만 update_stage_dates.stage_id로 한정했고 왼쪽을 빼먹었다. 양쪽 모두 한정한다.
--
-- 파라미터 이름은 바꾸지 않는다 — create or replace는 입력 파라미터 이름 변경을 허용하지
-- 않으므로(0051과 같은 시그니처를 유지해야 replace가 된다), 이름 대신 한정으로 해결한다.
-- 함수 본문만 교체하며 다른 함수·데이터는 건드리지 않는다.
-- 롤백: 0052_ch37_stage_dates_fix_ROLLBACK.sql (0051 시점 본문으로 되돌림)

-- ── 실행 전 확인 ──
--   select proname from pg_proc where proname='update_stage_dates';  → 1행(0051이 이미 적용됨)

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

  select s.kind, s.name, s.date_start, s.date_end
    into v_kind, v_name, v_old_s, v_old_e
    from stages s
    where s.id = update_stage_dates.stage_id and s.tournament_id = t_id;
  if v_kind is null then
    raise exception '단계를 찾을 수 없습니다';
  end if;

  -- P31: 그 단계에 기록이 있으면 일정도 못 바꾼다(코스·컷과 같은 조건).
  -- 양쪽 모두 한정한다 — 왼쪽을 안 하면 컬럼인지 파라미터인지 모호해 에러가 난다.
  if exists (select 1 from scores sc where sc.stage_id = update_stage_dates.stage_id)
     or exists (select 1 from plays pl where pl.stage_id = update_stage_dates.stage_id) then
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
    -- 지정일: 대회일 하나뿐이므로 종료일을 시작일과 같게 고정한다.
    v_new_e := p_date_start;
  end if;

  update stages s set date_start = p_date_start, date_end = v_new_e
    where s.id = update_stage_dates.stage_id and s.tournament_id = t_id;

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
--   기록 없는 단계에서 콘솔 [단계 행 › 일정] 저장이 성공하고,
--   tournament_edit_logs에 '단계 일정 변경 — 이름: 이전 → 이후'가 남으면 정상.
--
--   notify pgrst, 'reload schema';   ← 본문만 바뀌어도 한 번 돌려두면 안전하다.
