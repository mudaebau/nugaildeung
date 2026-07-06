# 누가일등 — 2단계 데이터베이스 설계서 (Supabase)

> 이 문서는 Claude Code의 작업 지시서다.
> 원칙: **이미 배포된 index.html을 부수지 않고, Supabase 연결을 한 조각씩 얹는다.**
> 프레임워크 전환(Next.js 등) 금지. 현재의 단일 HTML + 바닐라 JS 구조를 유지하고
> supabase-js v2를 CDN(`https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2`)으로 불러온다.

---

## 0. 배경

- index.html은 "누가일등" 파크골프 대회 운영 모바일웹의 완성된 프로토타입.
- 현재 모든 데이터가 브라우저 메모리에만 존재 → 새로고침 시 소실.
- 목표: 대회/참가자/점수가 Supabase에 영구 저장되고, 심판 입력이 전광판에 실시간 반영.
- 운영자는 비개발자다. 각 작업 단계에서 무엇을 하는지 한 문장씩 설명할 것.

---

## 1. 테이블 설계 (5개)

### operators — 운영자 (회원)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | 자동 생성 |
| phone | text UNIQUE | 전화번호 = 계정 (예: 010-1234-5678 정규화 저장) |
| name | text | 운영자 이름 |
| created_at | timestamptz | 가입 시각 |

### tournaments — 대회
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| owner_id | uuid FK→operators | 대표운영자 |
| name | text | 대회명 |
| host_org | text | 주최·주관 |
| date_start / date_end | date | 대회 기간 |
| rounds | int (1~4) | 코스 수 (18홀=1 … 72홀=4) |
| venues | jsonb | 골프장명 배열 `["솔터공원 파크골프장", ...]` |
| course_pars | jsonb | 코스별 파 배열 `[[3,4,3,...18개], ...]` |
| tie_rule | text | 동점 처리 (최종 코스 카운트백 / 연장전 / 연장자 우선 / 별도선정) |
| cap | int | 모집 정원 |
| fields | jsonb | 참가자 정보 항목 설정 `{"name":true,"sex":true,"age":true,"club":true,"nick":false,"region":false}` |
| awards | jsonb | 시상 부문 `{"gender":true,"age":false,"club":false}` |
| status | text | ready / open / live / done |
| created_at | timestamptz | |

### staff — 운영스탭 (가입 없음, 토큰 링크로 접속)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| tournament_id | uuid FK→tournaments | on delete cascade |
| name / phone / duty | text | 이름, 전화번호, 담당 |
| can_score | boolean | 점수 입력 권한 |
| token | uuid UNIQUE | 심판 링크 키. 접속 주소: `?j={token}` |
| link_opened_at | timestamptz NULL | 링크 최초 접속 시각 (미접속=NULL) |

### players — 참가자 (대기자 포함)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| tournament_id | uuid FK→tournaments | on delete cascade |
| name | text | |
| phone | text | **(tournament_id, phone) UNIQUE** — 대회 내 중복 접수 차단 |
| sex / club / region / nick | text NULL | 대회 fields 설정에 따라 선택 수집 |
| age | int NULL | |
| status | text | ok(정상) / wd(기권) / dq(실격) / wait(대기자) |
| group_no | int NULL | 조 번호 (0부터), 미배정 NULL |
| group_order | int NULL | 조 내 순서 |
| created_at | timestamptz | 접수 순서 = 대기 순번의 근거 |

### scores — 점수 (선수 1명 × 1홀 = 1행)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| tournament_id | uuid FK | |
| player_id | uuid FK→players | on delete cascade |
| hole_index | int | 0~71 전역 인덱스. 코스 = floor(hole_index/18), 홀 = hole_index%18+1 |
| strokes | int (1~15) | 타수 |
| entered_by | uuid FK→staff NULL | 입력 심판 (운영자 직접 입력 시 NULL) |
| updated_at | timestamptz | |
| | | **(player_id, hole_index) UNIQUE** — upsert 대상 |

### score_logs — 점수 변경 이력 (감사 로그, 수정·삭제 불가)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | bigint identity PK | |
| tournament_id / player_id / hole_index | | 대상 |
| old_strokes | int NULL | 신규 입력이면 NULL |
| new_strokes | int | |
| reason | text NULL | 정정 사유 (오기입/스코어 재확인/운영자 지시). 신규 입력은 NULL |
| entered_by | uuid NULL | |
| created_at | timestamptz | |

> scores에 insert/update가 일어날 때마다 score_logs에 1행 추가 (DB 트리거로 구현 권장 — 클라이언트가 누락해도 이력이 남도록).

---

## 2. 실시간 · 보안 방침

- **Realtime**: `scores`, `players` 테이블에 Supabase Realtime 활성화.
  전광판 화면은 해당 tournament_id의 scores 변경을 구독해 리더보드를 다시 계산한다.
- **RLS(행 수준 보안)**: 파일럿 단계 방침 —
  - tournaments / players / scores: **읽기 공개** (전광판·대회 리스트가 공개 페이지이므로)
  - 쓰기: anon 키로 허용하되, 점수 쓰기는 반드시 유효한 staff token과 함께 오는 경우만
    (token 검증은 Supabase RPC 함수 `submit_score(token, player_id, hole_index, strokes, reason)` 하나로 감싸서 처리 — 클라이언트가 scores에 직접 insert하지 않게 한다)
  - operators 로그인: 파일럿에서는 전화번호+이름 매칭의 간이 방식(문자 OTP는 3단계 이후). 단, 이 한계를 코드 주석에 명시할 것.
- 전화번호는 저장 전 `010-0000-0000` 형식으로 정규화.

---

## 3. 구현 순서 (한 번에 하나씩, 각 단계 끝날 때마다 push & 배포 확인)

1. **스키마 생성** — 위 테이블 SQL을 Supabase에 적용 (마이그레이션 파일로 저장소에 보관)
2. **대회 개설 저장** — 위저드 완료 시 tournaments+staff insert. 홈 리스트가 DB에서 로드되게 전환 (기존 샘플 대회는 시드 데이터로 DB에 넣는다)
3. **참가 신청 저장** — 개인/단체 접수 → players insert. 정원 초과 시 status='wait'. 중복 전화번호는 UNIQUE 제약으로 차단하고 안내
4. **조편성 저장** — group_no/group_order update. 맞바꾸기 반영
5. **심판 토큰 링크** — `?j={token}` 접속 시 해당 스탭의 입력 화면만 표시 + link_opened_at 기록. 운영 탭 발송 현황이 실데이터로
6. **점수 입력 실시간** — submit_score RPC + score_logs 트리거 + 전광판 Realtime 구독. `?board={tournament_id}` 로 전광판 직접 접속
7. **신청 페이지 직접 접속** — `?apply={tournament_id}`

## 4. 하지 말 것

- Next.js/React 전환, 빌드 도구 도입, 파일 분리 리팩토링 (요청 전까지 금지)
- 프로토타입의 화면·디자인 변경 (이번 단계는 데이터 연결만)
- service_role 키를 클라이언트 코드에 넣는 것 (anon 키만 사용)
- Supabase URL/anon 키를 GitHub에 하드코딩해도 되는지 물어보지 말 것 — anon 키는 공개되어도 되는 키이므로 index.html 상단 상수로 넣되, 주석으로 그 이유를 남길 것
