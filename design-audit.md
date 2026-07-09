# 누가일등 v2.3 — 디자인·구현 점검 보고서

> 점검 기준: ① [nuga1-v23-workorder.md](nuga1-v23-workorder.md) 차수 0~10 각 항목의 확인 조건 ② 디자인 목업 3종 — [nuga1-v23-mockup.html](design/nuga1-v23-mockup.html)(5장면) · [nuga1-subtab-mockup.html](design/nuga1-subtab-mockup.html)(A안) · [nuga1-board-redesign.html](design/nuga1-board-redesign.html)(B안) ③ 지시서 공통 규칙 — kv행·표 신규 금지 / 옐로우는 1등·내 것 전용 / 굵기 최대 700 / 전광판 고정 px 컬럼 금지 / tournaments 테이블 UPDATE RLS 금지
> 독립 검증 에이전트가 코드를 처음부터 다시 읽어 차수별 항목과 규칙 위반을 확인했다. 에이전트가 "미구현"으로 보고한 1건(차수6 수정 이력 UI)은 실제로는 `tournament_edit_logs` 테이블명 불일치로 인한 오탐이었음을 재확인해 정정했고, 실제로 발견된 위반 1건(히어로 배지 로고 SVG의 `font-weight="900"`)은 점검 중 함께 수정했다.

## 요약

| 항목 | 상태 |
|---|---|
| 차수 1 — 홈 히어로 | **완료** |
| 차수 2 — 서브탭 A안 + 관리홈 도구 정리 | **완료** |
| 차수 3 — 단계 중심 관리홈 | **완료** |
| 차수 4 — 스코어·리더보드 단계 구분 + 입력 이원화 | **완료** |
| 차수 5 — 참가자 탭(체크인·입금·직접 추가) | **완료** |
| 차수 6 — 대회 정보 수정 3등급 | **완료** |
| 차수 7 — 위저드 3건 | **완료** |
| 차수 8 — 전광판 B안 + 성별 필터 | **완료** |
| 차수 9 — 기록 입력 방식 옵션(홀별/총점만) | **완료** |
| 차수 10 — 전광판 범위 축(종합/코스별) | **완료** |
| 표 폐지 (kv행·표 신규 금지) | **완료 — 잔여 0건(인쇄용 예외 1건만)** |
| 옐로우 사용 (1등·내 것 전용) | **완료 — 위반 0건** |
| 폰트 굵기 (최대 700) | **완료 — 위반 0건(점검 중 1건 발견해 수정)** |
| 전광판 컬럼 폭 (고정 px 금지) | **완료 — fr 비율 전환 확인** |
| tournaments UPDATE RLS 금지 | **완료 — 위반 0건** |

전체 10개 차수 + 5개 규칙 검사 **전부 완료**, 잔여 위반 0건. v2.3 종료 조건을 충족한다.

---

## 차수 1 — 홈 히어로

`.hero` 배경 그라디언트 `linear-gradient(150deg,#5A9ADA,var(--main-deep))`(#5A9ADA→#2F6BAA) 확인. 배지 로고(히어로 위 바탕 #224670) + 라벨 칩 "파크골프 대회 관리 플랫폼" + 헤드라인 "대회 개설부터 시상까지, 한 번에 끝내세요" + 흰색 CTA(딥블루 글자) 구조 확인. 피드 하단의 기존 개설 버튼은 제거되어 히어로의 CTA만 남아 있다.

## 차수 2 — 서브탭 A안 + 관리홈 도구 정리

`.tabA`에 관리홈·요강·참가자·운영진·스코어·리더보드·결과 7개 탭이 균등 폭·스크롤 없이 배치. 스코어 탭 `#scoreBadge`가 검수 대기 시 점 배지로 표시되고 해당 탭 진입 시 소거. 관리홈의 사진입력 도구 행은 제거되고 `#scoreTodo` 할 일 줄(탭 시 스코어 탭 이동)로 대체. 관리홈 도구는 [리더보드·전광판], [참가 신청 링크 공유]만 남음.

## 차수 3 — 단계 중심 관리홈

`#stageInfoCard`가 현재 진행 단계 현황만 표시, 다른 단계는 `#mgSub` 부제 한 줄로 안내. 하단 고정 버튼이 "[현 단계명] 마감하고 [다음 단계명] 시작"/마지막 단계 "결과·시상 확정"으로 동적 전환. `openStageSheet()` 확인 시트에 순위 확정·컷 선발·동점 규칙 안내·마감 경고가 모두 포함되고, 확정 시 기존 `doAdvanceStage()`/`finalizeTournament()`를 그대로 호출(중복 구현 없음). 완료 단계는 `viewStageResult()`로 읽기 전용 조회.

## 차수 4 — 스코어·리더보드 단계 구분 + 입력 이원화

`stageChipsHTML()` 기반 단계 칩이 스코어·리더보드 탭 상단에 공통 렌더링되고, 완료 단계는 "(확정)" 표기 후 조회 전용. 라운드형 스코어 탭의 [선수별|조별] 세그먼트, 선수별 홀 그리드(자동 이동·소계·파란 테두리)와 조별 홀 단위 입력 모두 확인. 정정 시 `applyCorr()` 플로우 + `score_logs` 기록. 리더보드 탭의 "[단계명] 최종순위 확정" 버튼이 `openStageSheet()`를 그대로 재사용.

## 차수 5 — 참가자 탭(체크인·입금·직접 추가)

명단 행의 체크인 동그라미(`toggleCheckin()`, DB 반영)와 입금/미입금 뱃지(`togglePaid()`) 확인, 앱바 부제 "참가자 N명 · 출석 N · 입금 N" 집계. `players.checked_in_at`/`paid` 컬럼 마이그레이션(0020) 확인. [참가자 추가] 버튼은 전화번호 형식 검증 + `23505` 중복 에러 처리, 접수 마감 여부와 무관하게 동작. 정원 초과 시 [대기자로 추가]/[정원 늘려서 확정](`increase_tournament_cap` RPC) 선택지 확인.

## 차수 6 — 대회 정보 수정 3등급

요강 탭 [수정하기] + 관리홈 [대회 정보 수정] 진입점 확인. `renderEditInfoList()`가 항목별 섹션 목록(위저드 재실행 아님)을 보여주고, 탭하면 필드 수정 화면으로 이동. ①자유(대회명·주최·시상·요강정보)는 `update_tournament_free_info` RPC로 즉시 저장. ②경고(일정·장소·정원·참여대상·공개설정)는 `openWarnEdit()` 확인창 필수, 정원 축소 시 초과분이 `saveEditCap()`에서 자동 대기 전환. ③잠금(코스 구성·파·단계 구조·컷)은 `editStageLocked`(해당 단계 scores/plays 존재 여부)에 따라 수정 폼 대신 잠금 안내만 노출.

**수정 이력**: `tournament_edit_logs` 테이블(마이그레이션 0021)에 모든 수정이 who/what/when으로 기록되고, `renderEditHistory()`가 `#editHistoryCard`에 최근 10건을 렌더링한다(독립 검증 에이전트가 테이블명을 `edit_history`로 잘못 검색해 "미구현"으로 오판했던 항목 — 실제 코드에서 `renderEditHistory`/`editHistoryCard`/`tournament_edit_logs` 참조를 직접 확인해 정정).

`tournaments` 테이블은 마이그레이션 전체에서 anon UPDATE 정책이 0건 확인되어(§ 규칙 검사 참고) 0017의 원칙이 v2.3 내내 유지되었다.

## 차수 7 — 위저드 3건

wpStage1/2/3 모두 `fHoles`/`fHoles2`/`fHoles3`에 72홀(4개 코스) 옵션 존재. "매장"→"코스" 라벨 전면 교체 확인(기간형 개별 기록의 "플레이 매장" 필드와 스크린 유형 설명 문구는 지시서 예외대로 유지). 시상 부문 토글이 `wpParticipantInfo`에서 `wpAwards`로 이동, `AWARD_FIELD_DEP` 기반 양방향 의존성(부문 ON→항목 자동 ON+토스트, 항목 OFF 시도→차단+경고) 확인.

## 차수 8 — 전광판 B안 + 성별 필터

`.boardshell` 배경이 `linear-gradient(170deg,#3D71A9,#2E5C8D)`로 교체되고 Black Han Sans 참조는 코드 전체(폰트 임포트 포함)에서 0건. 이름 Noto Sans KR 600(1위 700), 숫자 Oswald, 행 줄무늬(`nth-child(odd)`), 1위 옐로우 좌측 바+틴트+순위·합계 옐로우, 언더파 `#FFB49E` 모두 확인. 성별 필터(전체/남자부/여자부)는 `config.fields.sex`가 꺼지면 숨겨지고, TV 자동 순환(20초/10초/10초)은 성별만 순환. 컬럼 폭은 `BOARD_COLS`(fr 단위) 사용. 운영자 리더보드 탭은 동일 보드 화면을 그대로 열어 별도 구현 없이 같은 필터를 공유한다.

## 차수 9 — 기록 입력 방식 옵션(홀별/총점만)

`stages.record_mode`(마이그레이션 0022) 확인. 위저드 각 단계 패널에 [홀별 기록]/[총점만] 선택지, `submit_play` RPC가 `kind='period' or record_mode='total'` 조건으로 라운드+총점만 단계도 처리하며 라운드는 delete-then-insert(코스당 1행), 기간형은 insert-always(전 기록 보관)로 분기. 동점 처리 드롭다운은 총점만 선택 시 "카운트백" 옵션이 숨겨지고 안내 문구 노출. 기간형 기록 제출 시 베스트 갱신/유지 토스트 확인.

## 차수 10 — 전광판 범위 축(종합/코스별)

`boardScopeChipsHTML()`이 `ROUNDS>=2`일 때만 [종합|1코스|2코스|…] 노출, `boardGenderFilter`와 독립적으로 조합 가능. 종합 보기에서 다코스면 `showSubtotal` 분기로 코스별 소계 컬럼(1C/2C…) 추가, 기간형·총점만 단계는 소계 자리에 코스별 베스트(`bestArr`)를 표시. 코스별 보기는 `standings(pool, courseIdx)`/`periodStandings(pool, courseIdx)`로 해당 코스만 재순위. TV 자동 순환은 `startAutoRotate()`에서 `boardGenderFilter`만 순환하고 `boardScopeFilter`는 건드리지 않는다.

---

## 규칙 위반 검사

### 표 폐지 — 완료 (잔여 0건)

`<table` 검색 결과 인쇄용 결과지(`#rtablePrint`, `display:none`+`@media print`) 1건만 존재. v2.2 감사 이후 신규 표 없음.

### 옐로우 사용 — 완료 (위반 0건)

`--sun`/`#F7CF5C` 사용처(히어로 LIVE 카드 1위, 전광판 1위 rank/total, 결과 포디움 1위, 결과 순위 리스트 1위, 홈 "내 대회" 라벨 등) 전부 1등 또는 "내 것" 맥락에 한정.

### 폰트 굵기 — 완료 (점검 중 1건 발견해 수정)

CSS `font-weight:800`/`900` 검색 결과 0건. 단, 독립 검증 중 히어로 배지 로고의 **인라인 SVG** `font-weight="900"`(CSS가 아니라 SVG 속성이라 기존 grep 패턴에서 누락되어 있었음)를 발견해 `700`으로 수정했다. 현재 전체 굵기 위반 0건.

### 전광판 컬럼 폭 — 완료 (고정 px 금지 확인)

`BOARD_COLS`(`0.6fr 3fr 1fr 1fr 1fr`)와 `boardCols()`(다코스 시 `Array(ROUNDS).fill('0.7fr')`) 모두 fr 비율 기반. 차수8·10에서 도입한 컬럼 스타일에 고정 px 없음.

### tournaments UPDATE RLS 금지 — 완료 (위반 0건)

`supabase/migrations/*.sql` 전체에서 `tournaments` 테이블에 대한 anon UPDATE 정책 0건. 차수6에서 추가한 자유/경고 등급 필드 수정은 모두 security-definer RPC(`update_tournament_free_info`, `update_tournament_warned_info`)를 통해서만 이뤄진다.

---

## 결론

v2.3 차수 1~10의 확인 조건을 모두 충족했고, 독립 검증 중 발견한 실제 위반 1건(히어로 로고 SVG 굵기 900)은 즉시 수정했으며 오탐 1건(차수6 수정 이력 UI)은 코드 재확인으로 정정했다. 잔여 위반 0건.

이제 워크오더에 명시된 대로 **v2.3 완료를 선언**하고, 이후 출시 전 점검(성능·개인정보 동의·오프라인 대비)과 파일럿, 예약된 v2.4(PC/와이드 대응)로 넘어갈 수 있다.
