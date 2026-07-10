-- 차수16 ②-후속: access_code를 "소유자 증명"으로 쓰던 0026 초안을 폐기하고,
-- 진짜 운영자 자격 증명(operators.secret) 기반으로 다시 설계한다.
--
-- 문제: update_tournament_warned_info 등 관리자 전용 RPC들은 t_id(URL에 노출되는,
-- 비밀 아닌 값)만 알면 누구나 호출할 수 있었다 — 소유자 확인이 전혀 없었다.
-- access_code를 "현재 값을 아는지"로 검증하는 방식은 두 가지 문제가 있었다:
--   ① 공개 대회는애초에 access_code가 없어 검증이 통과되지 않고 그대로 뚫려 있었다
--      (공개 대회를 private+임의 코드로 바꿔치기 가능).
--   ② 그 상태에서 진짜 운영자는 자신이 모르는 코드를 알아야 되돌릴 수 있어
--      역으로 잠금 탈취(lockout)를 당할 수 있었다.
--
-- 조치: operators에 서버 발급 비밀값(secret)을 추가하고, 모든 운영자 전용 쓰기 RPC가
-- "호출자가 이 대회의 owner_id에 해당하는 operators.secret을 제시했는지"를 검증하도록 한다.
-- access_code는 원래 목적(입장 비밀번호)으로만 쓰고 소유자 증명에는 더 이상 관여하지 않는다.

alter table operators add column if not exists secret uuid not null default gen_random_uuid();

-- access_code(0024)와 같은 이유로 secret도 anon이 직접 select 할 수 없게 막는다.
-- (owner_id는 tournaments 행에서 공개적으로 보이므로, secret을 직접 조회할 수 있으면
--  이 마이그레이션의 목적 자체가 무의미해진다.)
revoke select (secret) on operators from anon;

-- 로그인/가입: 기존에는 클라이언트가 operators를 직접 upsert+select 했는데,
-- secret 컬럼 select가 막혔으므로 이제 이 RPC(security definer, 컬럼 권한 우회)를 통해서만
-- 발급된 secret을 돌려받는다.
create or replace function operator_signup(p_phone text, p_name text)
returns table(id uuid, name text, secret uuid)
language plpgsql security definer set search_path = public as $$
begin
  return query
    insert into operators as o (phone, name) values (p_phone, p_name)
    on conflict (phone) do update set name = excluded.name
    returning o.id, o.name, o.secret;
end;
$$;
grant execute on function operator_signup(text, text) to anon;

-- 공용 소유자 검증 헬퍼. 각 관리자 전용 RPC의 첫 줄에서 perform assert_owner(...)로 호출한다.
create or replace function assert_owner(t_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_owner_secret is null or not exists (
    select 1 from tournaments t join operators o on o.id = t.owner_id
    where t.id = t_id and o.secret = p_owner_secret
  ) then
    raise exception '이 대회의 운영자만 할 수 있는 작업입니다';
  end if;
end;
$$;

-- ① 기본 정보 수정
drop function if exists update_tournament_free_info(uuid,text,text,jsonb,text,jsonb,text,text,text,text);
create or replace function update_tournament_free_info(
  t_id uuid, p_name text, p_host_org text, p_awards jsonb,
  p_prize_total text, p_prizes jsonb, p_contact text, p_fee text, p_rules text,
  p_owner_secret uuid, p_who text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
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
grant execute on function update_tournament_free_info(uuid,text,text,jsonb,text,jsonb,text,text,text,uuid,text) to anon;

-- ② 경고 등급 수정 (일정·정원·참여대상·공개설정)
drop function if exists update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,text,text);
create or replace function update_tournament_warned_info(
  t_id uuid, p_date_start date, p_date_end date, p_cap int,
  p_eligibility jsonb, p_visibility text, p_access_code text, p_owner_secret uuid,
  p_who text, p_what text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update tournaments set
    date_start = p_date_start, date_end = p_date_end, cap = p_cap,
    visibility = p_visibility,
    access_code = case when p_visibility = 'private' then p_access_code else null end,
    notice_extra = coalesce(notice_extra,'{}'::jsonb) || jsonb_build_object('eligibility', p_eligibility)
  where id = t_id;
  insert into tournament_edit_logs(tournament_id, who, what) values (t_id, p_who, p_what);
end;
$$;
grant execute on function update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,uuid,text,text) to anon;

-- ③ 접수 마감/재개
drop function if exists set_registration_closed(uuid, boolean);
create or replace function set_registration_closed(t_id uuid, p_closed boolean, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_owner(t_id, p_owner_secret);
  update tournaments set reg_closed = p_closed where id = t_id;
end;
$$;
grant execute on function set_registration_closed(uuid, boolean, uuid) to anon;

-- ④ 대회 확정(finalize)
drop function if exists finalize_tournament(uuid);
create or replace function finalize_tournament(t_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
begin
  perform assert_owner(t_id, p_owner_secret);
  select status into v_status from tournaments where id = t_id;
  if v_status is null then
    raise exception '대회를 찾을 수 없습니다';
  end if;
  if v_status <> 'live' then
    raise exception '진행중(LIVE) 상태의 대회만 확정할 수 있습니다 (현재 상태: %)', v_status;
  end if;
  update tournaments set status = 'done' where id = t_id;
end;
$$;
grant execute on function finalize_tournament(uuid, uuid) to anon;

-- ⑤ 정원 직접 확장(참가자 추가 중 정원 초과 시)
drop function if exists increase_tournament_cap(uuid, int);
create or replace function increase_tournament_cap(t_id uuid, new_cap int, p_owner_secret uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_cap int;
begin
  perform assert_owner(t_id, p_owner_secret);
  if new_cap is null or new_cap < 1 then
    raise exception '정원은 1명 이상이어야 합니다';
  end if;
  update tournaments set cap = new_cap where id = t_id and new_cap > cap;
  select cap into v_cap from tournaments where id = t_id;
  return v_cap;
end;
$$;
grant execute on function increase_tournament_cap(uuid, int, uuid) to anon;

-- 아래 항목들은 이번 마이그레이션에서 다루지 않았다(코드 변경 없음) — 클라이언트 보고서 참고:
-- 단계 마감/시작(stages 직접 update), 참가자 직접 추가(players 직접 insert),
-- 체크인·입금 토글, 조편성(players 직접 update), 코스명/파/컷 수정(stages 직접 update).
-- 이들은 애초에 RPC가 아니라 원본부터 RLS(using(true)/with check(true))로 열려 있는
-- 직접 테이블 쓰기라 이번 assert_owner 패턴을 그대로 끼워 넣을 수 없고,
-- RPC로 전환하는 별도 작업이 필요하다.
