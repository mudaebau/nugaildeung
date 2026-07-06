# 누가일등 v2.1 — 작업 지시서 (단계 구조 개정판)

> v2 설계서를 대체한다. 핵심 변경: **대회 유형(필드/스크린)과 대회 구조(단계 구성)를 분리.**
> 모든 대회는 1~3개의 "단계(stage)"로 구성되며, 기간·코스·조편성·진출 컷은 단계의 속성이다.
> 기존 원칙 유지: 프레임워크 전환 금지, 파일 분리는 허용(빌드 없이), 한 Phase씩 진행,
> 비개발자 운영자 — 단계마다 한 문장 설명 + push + 확인 방법.

---

## 1. 데이터 구조 개정

### tournaments — 대회 껍데기 (구조 정보는 stages로 이관)
| 컬럼 | 설명 |
|---|---|
| id, owner_id, name, host_org | 기존 유지 |
| type | 'field' \| 'screen' (표기·기본값 용도. 구조를 강제하지 않음) |
| cap, fields, awards, notice_extra, status | 기존 유지 |
| date_start / date_end | **파생값**: 전체 단계의 최소 시작~최대 종료 (리스트 표시용, 단계 저장 시 자동 갱신) |
| ~~rounds, venues, course_pars, tie_rule~~ | → stages로 이동 |

### stages — 단계 (대회당 1~3행) ★신규
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| tournament_id | uuid FK | on delete cascade |
| seq | int | 1,2,3 (순서) |
| name | text | 예선 / 본선 / 결승 (기본값, 수정 가능) |
| kind | text | **'round'**(지정일 라운드) \| **'period'**(기간형 자유 플레이) |
| date_start / date_end | date | round면 동일 날짜, period면 기간 |
| venues | jsonb | 코스명 배열 (round 1~4개, period 1~6개) |
| course_pars | jsonb | 코스별 파 배열. period(스크린)는 코스당 총파만 int로 저장 가능 |
| use_groups | boolean | **조편성 사용 여부 (옵션)** |
| tie_rule | text | 동점 처리 (단계별로 다를 수 있음) |
| advance_cut | jsonb NULL | 다음 단계 진출 인원. `{"m":12,"f":12}` 또는 `{"total":24}`. 마지막 단계는 NULL |
| status | text | waiting / open / done |

### 점수 저장 — 단계 방식에 따라 두 갈래
- **kind='round'** → 기존 `scores`(홀별) 사용. `scores.stage_id uuid FK` 추가.
  - use_groups=true: 심판 홀별 입력(기존) + 사진 입력
  - use_groups=false: 조 없이 진행 — 사진/총타수 제출 입력이 기본, group_no는 NULL 허용
- **kind='period'** → `plays`(1회 플레이 = 1행) 사용. `plays.stage_id` 포함.
  - 컬럼: id, tournament_id, stage_id, player_id, course_no, strokes_total, played_at, store, source('staff'|'photo'), evidence_url, entered_by, created_at
  - 집계: 선수별 코스별 min(strokes_total) 합산. **전 코스 기록자만 순위**, 미완료자는 "n/코스수" 표시

### 진출(stage 전환) 처리
- 운영자가 "다음 단계 시작" 실행 → 현 단계 순위 확정 → advance_cut만큼 자동 선발
  - `{"m":12,"f":12}`: 남/여 각각 상위 N (동점은 해당 단계 tie_rule로)
  - `{"total":24}`: 전체 상위 N
- 선발자는 players에 표시: `players.current_stage int` (현재 참가 중인 단계 seq, 기본 1)
- 탈락자는 이전 단계 기록 유지, 다음 단계 화면에서 제외
- 선발 결과 화면 제공(진출자 명단 → 카톡 공유 이미지/문자 발송 훅)

### 마이그레이션 (기존 데이터 보호 — 필수)
- 기존 대회마다 stage 1행 자동 생성: seq=1, name='본선', kind='round',
  venues/course_pars/tie_rule/기간을 tournaments에서 복사, use_groups=true
- scores.stage_id를 해당 stage로 백필
- 검증: 기존 대회의 전광판·결과가 마이그레이션 전과 동일하게 표시되는지 확인 후 다음 진행

---

## 2. 개설 위저드 개정 (Phase A 대화형 스텝 문법)

1. 기본 정보 — 대회명, 주최, 유형(필드/스크린), 정원
2. **"몇 단계 대회인가요?"** — 1단계 / 2단계(예선→결승) / 3단계(예선→본선→결승)
3. 단계별 설정 카드 (선택 수만큼 반복):
   - 방식: 지정일 라운드 / 기간형 자유 플레이
   - 날짜 또는 기간
   - 코스 (+ round면 파 편집)
   - **조편성 사용** 토글 (period는 기본 OFF·숨김, round는 기본 ON)
   - 마지막 단계가 아니면: **진출 인원** — 남/여 구분 입력 또는 전체 인원 (라디오)
   - 동점 처리
4. 참가자 정보 항목·시상 부문 (기존)
5. 요강 정보 (선택)

기본 프리셋 제공: 유형=필드 → 1단계(round·조편성ON) 프리필, 유형=스크린 → 2단계(period→round) 프리필. **프리셋은 출발점일 뿐, 모든 조합 수정 가능.**

---

## 3. 화면 반영 규칙

- 대회 상세/운영 탭 상단에 **단계 스테퍼** 표시: `예선(진행중) → 결승(대기)` — 현재 단계가 모든 화면의 컨텍스트
- 전광판: 단계 선택 칩 추가(기본=진행 중 단계). period 단계는 코스별 베스트+합산 보드, **컷라인(진출선) 표시** + 남/여 탭. round 단계는 기존 보드
- 요강(Phase B): 일정 섹션이 단계 테이블로 자동 구성 (예선 기간 / 결승 일시·컷)
- 조편성 탭: use_groups=false 단계에서는 비활성 안내 표시
- 점수 입력 진입점이 단계 방식을 따라감: round→심판 링크(+사진), period→기록 입력(선수 검색→코스→총타수, +사진)

---

## 4. Phase 순서 (개정)

| Phase | 내용 |
|---|---|
| A | 디자인 시스템 v2 규칙 확정 + 로고 적용 (기존 설계서 Phase A 그대로) |
| B | 요강 자동 생성 + PDF (기존 그대로. 단, 일정 섹션은 단계 구조를 읽도록) |
| C | 스코어카드 사진 입력 (기존 그대로. scores/plays 양쪽에서 사용 가능하게 source·evidence 설계) |
| **D1** | **stages 구조 도입 + 마이그레이션** — 기존 필드 단판이 1단계 대회로 무손실 흡수되는 것까지 |
| **D2** | **기간형(period) 단계 + plays + 진출 컷/단계 전환** — 스크린대회 완성 |
| E | 기존 화면 리디자인 전환 (기존 그대로) |

D를 D1/D2로 쪼갠 이유: 마이그레이션(위험 구간)을 격리해 검증한 뒤 신기능을 얹는다.

## 5. 하지 말 것
- stages 없이 tournaments에 단계 필드를 늘리는 편법
- 마이그레이션 검증 전 D2 착수
- 결선용 점수 시스템 신설 (round 단계 = 기존 scores 재사용)
- 사진 판독 무검수 저장 / 옐로우 남용 / 800↑ 굵기 / kv행·표 신규 사용
