-- CH33-B: "스코어 확정"(정정 잠금 시점) — stages.scores_locked 플래그.
-- 순수 추가: (1) 컬럼 default false → 기존 대회·기존 동작 무영향(전부 잠금 해제 상태)
--            (2) scores/plays INSERT·UPDATE 트리거로 잠금 시 전 경로(운영자·심판 토큰·모바일)
--                차단 — 기존 스코어 쓰기 RPC 8종을 하나도 건드리지 않는다(재작성 0).
--            (3) 잠금/해제 RPC(owner) — 확정·확정 취소(로그).
-- DELETE는 트리거로 막지 않는다(대회 삭제 cascade 안전) — 잠금 시 삭제 UI는 클라이언트가 가린다.
-- 진출자 확정(컷)은 잠금(확정)을 전제로 클라이언트가 순서를 강제한다.
-- 롤백: 0047_ch33_scores_locked_ROLLBACK.sql

-- (1) 컬럼 — 순수 추가
alter table stages add column if not exists scores_locked boolean not null default false;

-- (2) 잠금 가드 트리거 — scores·plays 공용(둘 다 stage_id 보유)
create or replace function ch33_block_locked_scores() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_locked boolean;
begin
  select scores_locked into v_locked from stages where id = NEW.stage_id;
  if coalesce(v_locked,false) then
    raise exception '스코어가 확정(잠금)된 단계입니다 — 콘솔에서 [확정 취소] 후 입력·정정할 수 있습니다';
  end if;
  return NEW;
end;
$$;
drop trigger if exists trg_scores_locked on scores;
create trigger trg_scores_locked before insert or update on scores
  for each row execute function ch33_block_locked_scores();
drop trigger if exists trg_plays_locked on plays;
create trigger trg_plays_locked before insert or update on plays
  for each row execute function ch33_block_locked_scores();

-- (3) 확정/확정 취소 RPC (owner 전용, 로그)
create or replace function lock_stage_scores(t_id uuid, stage_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  perform assert_owner(t_id, p_owner_secret);
  update stages set scores_locked = true where id = stage_id and tournament_id = t_id and status = 'open'
    returning name into v_name;
  if v_name is null then raise exception '진행 중인 단계만 확정할 수 있습니다'; end if;
  insert into tournament_edit_logs(tournament_id, who, what)
    values (t_id, '운영자', v_name || ' 스코어 확정(정정 잠금)');
end;
$$;
grant execute on function lock_stage_scores(uuid,uuid,uuid) to anon;

create or replace function unlock_stage_scores(t_id uuid, stage_id uuid, p_owner_secret uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  perform assert_owner(t_id, p_owner_secret);
  -- 마감(done) 전에만 확정 취소 허용
  update stages set scores_locked = false where id = stage_id and tournament_id = t_id and status = 'open'
    returning name into v_name;
  if v_name is null then raise exception '마감된 단계는 확정을 취소할 수 없습니다'; end if;
  insert into tournament_edit_logs(tournament_id, who, what)
    values (t_id, '운영자', v_name || ' 스코어 확정 취소(정정 재개)');
end;
$$;
grant execute on function unlock_stage_scores(uuid,uuid,uuid) to anon;

-- ── 실행 후 확인 ──
--   select column_name from information_schema.columns where table_name='stages' and column_name='scores_locked'; → 1행
--   select tgname from pg_trigger where tgname in ('trg_scores_locked','trg_plays_locked'); → 2행
--   (잠금 후) plays insert 시도 → '스코어가 확정(잠금)된 단계입니다…' 예외
