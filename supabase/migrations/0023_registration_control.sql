-- 차수12: 접수 수동 마감/재개. tournaments UPDATE RLS는 열지 않는다(0017 원칙 유지) —
-- 전용 RPC(security definer)로만 처리한다.

alter table tournaments add column if not exists reg_closed boolean not null default false;

create or replace function set_registration_closed(t_id uuid, p_closed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update tournaments set reg_closed = p_closed where id = t_id;
end;
$$;
grant execute on function set_registration_closed(uuid, boolean) to anon;
