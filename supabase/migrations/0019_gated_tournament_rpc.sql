-- v2.2 차수 6: 비공개 대회 조회를 access_code를 받는 RPC로 감싼다.
-- 클라이언트가 tournaments를 select(*)로 직접 읽지 않고 이 함수를 통해서만
-- 접근하도록 하여, 비밀번호 없이는 실제 데이터(코스·정원 등)가 내려가지 않게 한다.
-- public 대회는 코드 없이 그대로 반환하고, private 대회는 코드가 맞을 때만
-- 전체 행을 반환하며 틀리거나 없으면 {id, visibility, gated:true}만 반환한다.

create or replace function get_tournament_gated(t_id uuid, p_code text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_row tournaments%rowtype;
begin
  select * into v_row from tournaments where id = t_id;
  if v_row.id is null then
    return null;
  end if;
  if v_row.visibility = 'public' or (p_code is not null and p_code = v_row.access_code) then
    return to_jsonb(v_row);
  end if;
  return jsonb_build_object('id', v_row.id, 'visibility', v_row.visibility, 'gated', true);
end;
$$;
grant execute on function get_tournament_gated(uuid, text) to anon;
