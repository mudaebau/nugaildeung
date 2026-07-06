-- 설계 변경: 향후 'screen'(스크린 파크골프) 타입 대회를 구분하기 위한 자리만 미리 만들어 둔다.
-- 지금은 모든 대회가 'field'(필드) 타입이며, 앱 로직에서는 아직 사용하지 않는다.

alter table tournaments add column type text not null default 'field';
