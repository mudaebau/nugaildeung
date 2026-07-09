-- 차수5: 참가자 체크인·입금 상태 + 정원 초과 시 직접 추가(정원 확장) 지원.
-- tournaments UPDATE RLS는 열지 않는다(0017 원칙 유지) — cap 변경은 전용 RPC로만.

alter table players add column if not exists checked_in_at timestamptz;
alter table players add column if not exists paid boolean not null default false;

drop function if exists increase_tournament_cap(uuid, int);
create or replace function increase_tournament_cap(t_id uuid, new_cap int) returns int
language plpgsql security definer set search_path = public as $$
declare v_cap int;
begin
  if new_cap is null or new_cap < 1 then
    raise exception '정원은 1명 이상이어야 합니다';
  end if;
  update tournaments set cap = new_cap where id = t_id and new_cap > cap;
  select cap into v_cap from tournaments where id = t_id;
  return v_cap;
end;
$$;
grant execute on function increase_tournament_cap(uuid, int) to anon;
