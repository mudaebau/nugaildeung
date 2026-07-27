# 누가일등 — 데이터·보안 모델

> 정확한 DDL의 원본은 Supabase(마이그레이션 0001~0026+). 이 문서는 설계 의도 기준.

## 1. 핵심 테이블
| 테이블 | 역할 | 주요 컬럼(의도) |
|---|---|---|
| operators | 운영자 계정 | phone(=계정), name, **secret**(uuid, 소유자 증명 — anon SELECT 회수) |
| tournaments | 대회 | owner_id, title, host, type(field/screen), visibility(+access_code, anon SELECT 회수), status(recruit/live/done), cap(**null=무제한**), reg_closed, 기본정보 |
| stages | 단계 | tournament_id, no, kind(round/period), **score_mode(holes/total)**, 일정, courses(최대 4: 이름·홀수·파), grouping(bool), cut(남N/여N), tie_rule, status |
| players | 참가자 | tournament_id, name, phone(대회 내 유일), sex/age/club(설정 항목), status(확정/대기/기권), stage_no(현재 단계), group_no(단계 전환 시 초기화), checked_in_at, paid, 콜업/제외 사유 |
| scores | 홀별 기록 | player, stage, course, hole, strokes — score_mode=holes |
| plays | 총점 기록 | player, stage, course, strokes_total, played_at, venue — 기간형·총점만. **집계=코스별 min 합산(베스트), 전 기록 보관** |
| judges | 심판 | tournament, 담당(코스/조), **token**(링크 인증, 재발급·done 시 무효) |
| score_logs | 정정 로그 | 누가/언제/전후값/사유 — 수정·삭제 필수 동반 |
| tournament_edit_logs | 대회 수정 이력 | who/when/what (3등급 수정) |
| scorecard_photos | 사진 증빙 | **v3 보류 — 구조만 보존** |

## 2. 보안 모델
> 상태: HOTFIX-P0~CH28 적용 완료(0036~0040). players/scores/plays는 visibility=public 행 정책, 비공개는 게이트/운영자/심판 RPC로만. 마스킹=가운데 4자리 전부, 원문=get_player_phone 단건. 비공개 Realtime은 RLS 제약으로 6초 폴링 fallback.
- **쓰기는 전부 RPC** — players/stages/tournaments anon 직접 INSERT/UPDATE/DELETE 정책 0건
- **assert_owner(t_id, owner_secret)**: 모든 소유자 전용 RPC의 공통 관문 (operators.secret 대조)
  - 대상: 정보 수정(자유/경고), 접수 마감/재개, finalize, 정원, add/update/delete_player, promote_waitlist, set_group_assignments, create_stages, update_stage_*, advance_stage 등
- **apply_to_tournament**: 공개 신청 전용 RPC — 정원·중복 전화·마감·비공개 코드를 서버 단일 트랜잭션(행 잠금)으로 검증
- **비공개 게이트**: get_tournament_gated(코드 불일치=stub만). access_code·secret 컬럼 anon SELECT 회수
- **심판 토큰**: 범위 제한 입력 전용. done 후 submit 거부, 재발급 시 구 토큰 무효
- 점수 입력은 심판 토큰 체계(소유자와 별도 축)
- 한계(인지): 운영자 간이 인증 — 정식 오픈 전 문자 OTP 필수. secret 재발급·revoke는 CH28에서 추가
- 멱등 현황(감사): submit_score=UPSERT 안전 / plays=client_request_id 필요(CH28) / createTournament=제출 잠금 필요(CH28)

## 3. 개인정보
- 신청 시 수집·이용 동의 체크 필수(항목·목적·보유 1년), ?privacy 처리방침
- 전화번호: 공개 화면 원본 노출 0건 원칙, 운영자 화면도 마스킹(010-••••-1234)
- 삭제 요청 대응: 참가자 삭제 RPC(점수 존재 시 기권 유도) + 관련 기록 처리 원칙 문서화

## 4. 오프라인·복원력
- 점수 저장 실패 → 로컬 큐 → 연결 복구 시 자동 재전송, "N건 전송 대기" 배지
- **멱등키(CH28)**: 모든 기록·신청·전환 RPC에 client_request_id — 서버는 처리된 id면 기존 결과 반환(재전송 중복 방지). 끊김 순간 "서버 저장+클라이언트 실패 판단" 시나리오 대비
- Realtime 전략: 파일럿=Postgres Changes(채널은 tournament+stage 단위, 갱신은 짧은 간격 묶음) / 장애 시 5~10초 폴링 fallback / 정식 확장 시 Broadcast 검토
- 전광판 Realtime 끊김 → 재접속 배지 → 재구독 + 전체 재조회로 누락 보정
- 최후 백업: 종이 스코어카드 (사진 입력은 v3)

## 5. 집계 규칙 (분쟁 방지 핵심)
- 기간형 순위 = 선수별 **코스별 베스트 합산**. 재도전=기록 추가(경신 토스트), 오입력=기록 내역 시트에서 수정/삭제(사유+재계산)
- 컷 = 남N/여N 분할. 동점: 규칙 자동 해소 시도 → 불가 시 자동 선발 금지, [전원 진출|수동 선택]+로그
- 총점만 단계: 홀 카운트백 불가 → 동점 선택지에서 제외(최종 코스 총점/연장/연장자/별도선정)
- done 이후 모든 기록 불변
