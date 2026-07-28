-- ROLLBACK of 0052 — 0051 시점 본문(모호성 버그 포함)으로 되돌린다.
-- 실무에서 이걸 쓸 일은 거의 없다(0052는 순수 버그 수정이라 되돌리면 다시 고장난다).
-- 함수를 아예 없애려면 0051_ch37_stage_dates_ROLLBACK.sql을 쓸 것.
create or replace function update_stage_dates(
  t_id uuid, p_owner_secret uuid, stage_id uuid,
  p_date_start date, p_date_end date, p_who text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_kind text; v_name text; v_old_s date; v_old_e date; v_new_e date;
begin
  perform assert_owner(t_id, p_owner_secret);
  select kind, name, date_start, date_end into v_kind, v_name, v_old_s, v_old_e
    from stages where id = stage_id and tournament_id = t_id;
  if v_kind is null then raise exception '단계를 찾을 수 없습니다'; end if;
  if exists (select 1 from scores where stage_id = update_stage_dates.stage_id)
     or exists (select 1 from plays where stage_id = update_stage_dates.stage_id) then
    raise exception '이 단계에 기록이 있어 일정을 바꿀 수 없습니다';
  end if;
  if p_date_start is null then raise exception '시작일을 입력해 주세요'; end if;
  if v_kind = 'period' then
    v_new_e := coalesce(p_date_end, p_date_start);
    if v_new_e < p_date_start then raise exception '종료일이 시작일보다 앞설 수 없습니다'; end if;
  else v_new_e := p_date_start; end if;
  update stages set date_start = p_date_start, date_end = v_new_e
    where id = stage_id and tournament_id = t_id;
  insert into tournament_edit_logs(tournament_id, who, what)
  values (t_id, coalesce(p_who,'운영자'), format('단계 일정 변경 — %s', v_name));
end;
$$;
