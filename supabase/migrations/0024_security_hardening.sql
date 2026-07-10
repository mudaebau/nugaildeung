-- 차수16: 보안 점검 중 발견한 실제 우회 경로 수정.
--
-- 문제: tournaments_select_public 정책이 using(true)라 비공개(private) 대회도
-- anon 키만 있으면 access_code 컬럼을 포함한 전체 행을 직접 select로 읽을 수 있었다.
-- get_tournament_gated RPC는 처음부터 "클라이언트가 select(*)로 직접 읽지 않고
-- 이 함수로만 접근"하는 것을 전제로 설계됐지만(0019 주석 참고), RLS/권한으로
-- 강제되어 있지 않아 앱 코드를 우회하면(curl, devtools 등) 비밀번호가 그대로 노출됐다.
--
-- 조치: anon 롤에서 access_code 컬럼 자체의 SELECT 권한을 회수한다.
-- 이제 access_code는 get_tournament_gated RPC(security definer, 컬럼 권한 우회)를
-- 통해서만 검증 가능하고, 값 자체를 클라이언트로 내려주지 않는다.
-- 개설자 자신의 코드는 위저드 입력 시점에 로컬(localStorage)에 저장해두고
-- 그 값을 재사용하도록 클라이언트를 함께 수정했다(서버 재조회 불필요).
revoke select (access_code) on tournaments from anon;

-- staff.token / players·scores·plays(비공개 대회) 노출은 이번 마이그레이션에서
-- 다루지 않았다 — 이 앱에 실제 사용자 인증(auth.uid() 기반 RLS)이 없어 "개설자 본인"과
-- "URL을 아는 제3자"를 서버에서 구분할 방법이 없다는 구조적 한계 때문이다.
-- 상세 내용과 권장 조치는 별도로 보고한다(코드 변경 없음, 정책 변경 없음).
