-- v2.2 차수 5: 위저드에 참여대상·공개설정·시상 개편·요강 부가정보 질문을 추가하며
-- 필요한 컬럼을 만든다.
--
-- visibility/access_code: 비공개 대회 여부와 입장 비밀번호. 실제 접근 제한(RPC 감싸기)은
-- 차수 6에서 처리하고, 이번 차수는 데이터를 만들고 저장하는 것까지만 다룬다.
-- notice_extra: 요강 페이지에 쓰는 부가 정보를 한 jsonb에 모은다.
--   { eligibility:{type:'open'|'restricted', text}, prize_total, prizes:[{label,item}],
--     contact, fee, rules }

alter table tournaments add column if not exists visibility text not null default 'public'
  check (visibility in ('public','private'));
alter table tournaments add column if not exists access_code text;
alter table tournaments add column if not exists notice_extra jsonb not null default '{}';
