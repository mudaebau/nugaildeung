-- 차수21 ①: stages 테이블에 대한 anon 직접 insert/update를 전부 없애고
-- 소유자 검증(assert_owner, 0026)을 거치는 RPC로 대체한다.

-- 대회 개설 시 1~3개 단계를 한 번에 생성한다.
-- p_stages: [{"seq":1,"name":"예선","kind":"round","date_start":"2026-01-01","date_end":"2026-01-01",
--             "venues":[...],"course_pars":[...],"use_groups":true,"tie_rule":"...",
--             "advance_cut":{"total":24}|null,"status":"open","record_mode":"hole"}, ...]
create or replace function create_stages(t_id uuid, p_owner_secret uuid, p_stages jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  insert into stages(tournament_id, seq, name, kind, date_start, date_end, venues, course_pars,
    use_groups, tie_rule, advance_cut, status, record_mode)
  select t_id, (s->>'seq')::int, s->>'name', s->>'kind',
    nullif(s->>'date_start','')::date, nullif(s->>'date_end','')::date,
    coalesce(s->'venues','[]'::jsonb), coalesce(s->'course_pars','[]'::jsonb),
    coalesce((s->>'use_groups')::boolean,true), s->>'tie_rule',
    s->'advance_cut', coalesce(s->>'status','waiting'), coalesce(s->>'record_mode','hole')
  from jsonb_array_elements(p_stages) as s;
end;
$$;
grant execute on function create_stages(uuid,uuid,jsonb) to anon;

create or replace function update_stage_venues(t_id uuid, stage_id uuid, p_owner_secret uuid, p_venues jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update stages set venues = p_venues where id = stage_id and tournament_id = t_id;
end;
$$;
grant execute on function update_stage_venues(uuid,uuid,uuid,jsonb) to anon;

create or replace function update_stage_course(
  t_id uuid, stage_id uuid, p_owner_secret uuid,
  p_course_pars jsonb, p_advance_cut jsonb, p_record_mode text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update stages set course_pars = p_course_pars, advance_cut = p_advance_cut, record_mode = p_record_mode
  where id = stage_id and tournament_id = t_id;
end;
$$;
grant execute on function update_stage_course(uuid,uuid,uuid,jsonb,jsonb,text) to anon;

-- 단계 마감(done)+다음 단계 시작(open)과 진출자의 current_stage 반영을 한 트랜잭션으로 처리한다.
create or replace function advance_stage(
  t_id uuid, cur_stage_id uuid, next_stage_id uuid, p_owner_secret uuid, p_advanced_player_ids uuid[]
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_next_seq int;
begin
  perform assert_owner(t_id, p_owner_secret);
  select seq into v_next_seq from stages where id = next_stage_id and tournament_id = t_id;
  if v_next_seq is null then
    raise exception '다음 단계를 찾을 수 없습니다';
  end if;
  update players set current_stage = v_next_seq
    where id = any(p_advanced_player_ids) and tournament_id = t_id;
  update stages set status = 'done' where id = cur_stage_id and tournament_id = t_id;
  update stages set status = 'open' where id = next_stage_id and tournament_id = t_id;
end;
$$;
grant execute on function advance_stage(uuid,uuid,uuid,uuid,uuid[]) to anon;
