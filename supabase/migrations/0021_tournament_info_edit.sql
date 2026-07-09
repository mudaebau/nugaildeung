-- 차수6: 대회 정보 수정(3등급) + 수정 이력 로그.
-- tournaments UPDATE RLS는 열지 않는다(0017 원칙 유지) — 자유/경고 등급 필드는
-- 전용 RPC(security definer)로만 수정한다. 코스 구성·파·컷은 stages 테이블에 있고
-- stages는 이미 anon UPDATE 정책이 열려 있어(0009) RPC 없이 클라이언트에서 직접 수정한다.

create table tournament_edit_logs (
  id bigint generated always as identity primary key,
  tournament_id uuid not null references tournaments(id) on delete cascade,
  who text not null,
  what text not null,
  created_at timestamptz not null default now()
);
alter table tournament_edit_logs enable row level security;
create policy "tournament_edit_logs_select_anon" on tournament_edit_logs for select using (true);
create policy "tournament_edit_logs_insert_anon" on tournament_edit_logs for insert with check (true);

-- ①자유 등급: 대회명·주최·시상·요강정보(총상금/주요시상/문의처/참가비/규칙)
create or replace function update_tournament_free_info(
  t_id uuid, p_name text, p_host_org text, p_awards jsonb,
  p_prize_total text, p_prizes jsonb, p_contact text, p_fee text, p_rules text, p_who text
) returns void
language plpgsql security definer set search_path = public as $$
begin
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
grant execute on function update_tournament_free_info(uuid,text,text,jsonb,text,jsonb,text,text,text,text) to anon;

-- ②경고 등급: 일정·정원·참여대상·공개설정 (장소는 stages.venues 직접 수정, 로그만 별도 기록)
create or replace function update_tournament_warned_info(
  t_id uuid, p_date_start date, p_date_end date, p_cap int,
  p_eligibility jsonb, p_visibility text, p_access_code text, p_who text, p_what text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  update tournaments set
    date_start = p_date_start, date_end = p_date_end, cap = p_cap,
    visibility = p_visibility,
    access_code = case when p_visibility = 'private' then p_access_code else null end,
    notice_extra = coalesce(notice_extra,'{}'::jsonb) || jsonb_build_object('eligibility', p_eligibility)
  where id = t_id;
  insert into tournament_edit_logs(tournament_id, who, what) values (t_id, p_who, p_what);
end;
$$;
grant execute on function update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,text,text) to anon;
