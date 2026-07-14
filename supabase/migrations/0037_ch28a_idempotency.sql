-- CH28-A: TECH-AUDIT-01/문서 v1.2 확정 범위 ①③ (SQL 부분).
-- ②(전역 상태 리셋)는 클라이언트 전용이라 이 파일에 없음.
-- 롤백: 0037_ch28a_idempotency_ROLLBACK.sql

-- ── 실행 전 확인(선택) ──
-- 1) 오버로드 중복 확인 — 2행 나오면(10-param 구버전 포함) 정리 대상 존재:
--   select oid::regprocedure from pg_proc where proname='update_tournament_warned_info';
-- 2) plays.client_request_id 컬럼 없음 확인:
--   select column_name from information_schema.columns where table_name='plays' and column_name='client_request_id'; → 0행

-- ── 실행 후 확인 ──
-- 1) 오버로드 1개만 남았는지(11-param 버전):
--   select oid::regprocedure from pg_proc where proname='update_tournament_warned_info'; → 1행만
-- 2) client_request_id 컬럼·유니크 인덱스 생성 확인:
--   select column_name from information_schema.columns where table_name='plays' and column_name='client_request_id'; → 1행
--   select indexname from pg_indexes where tablename='plays' and indexname='plays_client_request_id_key'; → 1행
-- 3) 멱등 동작 확인(같은 client_request_id로 두 번 호출 시 같은 id 반환, plays에 1행만 생성) — anon 키로:
--   select submit_play('<judge-token>','<player-id>',1,80,null,current_date,null,'11111111-1111-1111-1111-111111111111');
--   -- 위와 동일 호출을 다시 실행 → 같은 uuid 반환해야 하고 plays 테이블에는 1행만 있어야 함
--   select count(*) from plays where client_request_id='11111111-1111-1111-1111-111111111111'; → 1

-- ── ③ warned_info 구버전(10-param) 오버로드 정리 ──
-- 0035가 p_cap_unlimited/p_fields를 추가하며 새 11-param 버전을 만들 때 드롭
-- 시그니처가 안 맞아(구버전은 boolean 없는 10-param) 구버전이 안 지워지고
-- 오버로드로 남아있었다(TECH-AUDIT-01 ⑦ 발견). 지금 정확한 시그니처로 드롭.
drop function if exists update_tournament_warned_info(uuid,date,date,int,jsonb,text,text,uuid,text,text);

-- ── ① plays 멱등키 ──
-- period 단계는 재도전을 의도적으로 허용(insert만, delete 없음)하므로 기존 로직은
-- 그대로 두되, "같은 제출을 두 번 보냈을 때"(오프라인 큐 재전송·더블탭)만 걸러야 한다.
-- client_request_id: 클라이언트가 제출 1회당 생성하는 UUID, 재시도에도 동일 값 재사용.
alter table plays add column if not exists client_request_id uuid;
create unique index if not exists plays_client_request_id_key on plays(client_request_id) where client_request_id is not null;

drop function if exists submit_play(uuid, uuid, int, int, text, date, text);
create or replace function submit_play(
  p_token uuid, p_player_id uuid, p_course_no int, p_strokes_total int,
  p_store text default null, p_played_at date default current_date, p_evidence_url text default null,
  p_client_request_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_staff staff%rowtype;
  v_player players%rowtype;
  v_stage stages%rowtype;
  v_status text;
  v_id uuid;
begin
  -- 멱등: 이미 처리된 client_request_id면 그 결과를 그대로 반환(재시도 안전).
  if p_client_request_id is not null then
    select id into v_id from plays where client_request_id = p_client_request_id;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  select * into v_staff from staff where token = p_token;
  if v_staff.id is null or not v_staff.can_score then
    raise exception '유효하지 않거나 입력 권한이 없는 링크입니다';
  end if;
  select * into v_player from players where id = p_player_id;
  if v_player.id is null or v_player.tournament_id <> v_staff.tournament_id then
    raise exception '해당 대회의 참가자가 아닙니다';
  end if;

  select status into v_status from tournaments where id = v_player.tournament_id;
  if v_status = 'done' then
    raise exception '이 대회는 종료되어 더 이상 기록을 입력할 수 없습니다';
  end if;

  select * into v_stage from stages
    where tournament_id = v_player.tournament_id
      and (kind = 'period' or record_mode = 'total') and status = 'open'
    order by seq limit 1;
  if v_stage.id is null then
    select * into v_stage from stages
      where tournament_id = v_player.tournament_id and (kind = 'period' or record_mode = 'total')
      order by seq limit 1;
  end if;
  if v_stage.id is null then
    raise exception '이 대회에는 기록 입력 가능한 단계가 없습니다';
  end if;

  if v_stage.kind = 'round' then
    delete from plays where stage_id = v_stage.id and player_id = p_player_id and course_no = p_course_no;
  end if;

  insert into plays (tournament_id, stage_id, player_id, course_no, strokes_total, played_at, store, source, evidence_url, entered_by, client_request_id)
  values (v_player.tournament_id, v_stage.id, p_player_id, p_course_no, p_strokes_total, p_played_at, p_store,
    case when p_evidence_url is not null then 'photo' else 'staff' end, p_evidence_url, v_staff.id, p_client_request_id)
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function submit_play(uuid, uuid, int, int, text, date, text, uuid) to anon;
