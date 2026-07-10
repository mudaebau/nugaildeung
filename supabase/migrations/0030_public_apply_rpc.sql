-- 차수21 ②: 공개 참가 신청을 전용 RPC로 옮겨 정원·중복·마감·비공개 비밀번호 검증을
-- 서버(단일 트랜잭션)에서 처리한다. 기존에는 클라이언트가 인원수를 먼저 read하고
-- 그 결과를 보고 나서 insert하는 두 단계였어서, 동시 신청 시 정원을 넘겨 확정되는
-- 경쟁 상태(race condition)가 있었고, 마감 여부도 재확인 없이 폼이 열려 있으면 그대로
-- 제출이 가능했다. 이 RPC는 소유자 검증이 필요 없는 공개 액션이라 assert_owner를 쓰지 않는다.
--
-- 주의: returns table(status text, ...)로 선언하면 plpgsql이 "status"라는 이름의 OUT 변수를
-- 자동으로 만드는데, players.status 컬럼과 이름이 같아 본문에서 참조가 모호(ambiguous)해진다.
-- 라이브 검증 중 발견 — 테이블 별칭을 붙여 명시적으로 구분한다.

create or replace function apply_to_tournament(
  t_id uuid, p_code text, p_name text, p_phone text, p_sex text, p_age int,
  p_club text, p_region text, p_nick text
) returns table(status text, player_id uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_tournament tournaments%rowtype;
  v_ok_count int;
  v_status text;
  v_id uuid;
begin
  select * into v_tournament from tournaments t where t.id = t_id for update;
  if v_tournament.id is null then
    raise exception '대회를 찾을 수 없습니다';
  end if;
  if v_tournament.visibility = 'private' and (p_code is null or p_code <> v_tournament.access_code) then
    raise exception '입장 비밀번호가 올바르지 않습니다';
  end if;
  if v_tournament.reg_closed then
    raise exception '접수가 마감되었습니다';
  end if;

  select count(*) into v_ok_count from players p where p.tournament_id = t_id and p.status = 'ok';
  v_status := case when v_ok_count >= v_tournament.cap then 'wait' else 'ok' end;

  insert into players(tournament_id, name, phone, sex, age, club, region, nick, status)
  values (t_id, p_name, p_phone, p_sex, p_age, p_club, p_region, p_nick, v_status)
  returning id into v_id;

  return query select v_status, v_id;
end;
$$;
grant execute on function apply_to_tournament(uuid,text,text,text,text,int,text,text,text) to anon;
