// 집계 로직(순위·컷·동점·기간형 베스트) 단위 테스트.
// node --test test/ 로 실행(외부 패키지 없음, Node 내장 test 러너).
// 대상 함수는 test/loadAggregation.js가 index.html에서 직접 추출한다 — 여기서는
// 로직을 재구현하지 않고, 실제 배포되는 코드를 그대로 검사한다.
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadAggregation } = require('./loadAggregation');

function player(name, { age = 40, st = '', scores = [] } = {}) {
  return { name, age, st, scores };
}
// HOLES=18*ROUNDS, 코스마다 동일 타수를 친 것으로 채워 sums()의 rt[]가 코스별 그 값이 되게 한다.
function flatScores(perCourseTotals, holesPerCourse = 18) {
  const arr = [];
  perCourseTotals.forEach(total => {
    const per = Math.floor(total / holesPerCourse);
    const rem = total - per * holesPerCourse;
    for (let h = 0; h < holesPerCourse; h++) arr.push(per + (h < rem ? 1 : 0));
  });
  return arr;
}
function evenPars(par, rounds) { return Array.from({ length: rounds }, () => Array(18).fill(par / 18)); }

test('순위(standings) — topar 오름차순, 미출전(thru=0)은 뒤로', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 1; sb.coursePars = evenPars(66, 1);
  const players = [
    player('A', { scores: flatScores([70]) }), // topar +4
    player('B', { scores: flatScores([64]) }), // topar -2
    player('C', { scores: Array(18).fill(null) }), // 미출전
  ];
  const order = sb.standings(players).map(s => s.p.name);
  assert.deepEqual(order, ['B', 'A', 'C']);
});

test('순위(standings) — topar/총타 동률 시 최종 코스 카운트백', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 2; sb.coursePars = evenPars(66, 2);
  const players = [
    player('A', { scores: flatScores([66, 70]) }), // 합 136, 2코스 70
    player('B', { scores: flatScores([70, 66]) }), // 합 136, 2코스 66(더 좋음)
  ];
  const order = sb.standings(players).map(s => s.p.name);
  assert.deepEqual(order, ['B', 'A']); // 최종 코스(2코스) 타수 낮은 B가 위
});

test('컷 cutCompetitors — 남N/여N 분리 계산', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 1; sb.coursePars = evenPars(66, 1);
  const men = [65, 66, 66, 68].map((t, i) => ({ p: { sex: '남' }, tot: t }));
  const women = [70, 71].map((t, i) => ({ p: { sex: '여' }, tot: t }));
  const doneArr = [...men, ...women].sort((a, b) => a.tot - b.tot);
  // 남 컷 2명 경계(66,66) margin 2 이내 동타 포함 카운트
  const n = sb.cutCompetitors(doneArr, { m: 2, f: 1 }, 2);
  assert.ok(n >= 3); // 남자부 66/66 동타 2명 이상 + 경계 margin 포함
});

test('컷 동점 자동 해소 — 최종 코스 카운트백으로 해소됨', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 2; sb.coursePars = evenPars(66, 2);
  const players = [
    player('A', { scores: flatScores([66, 70]) }), // 합 136
    player('B', { scores: flatScores([68, 68]) }), // 합 136, topar 동일
    player('C', { scores: flatScores([70, 70]) }), // 합 140
  ];
  const doneArr = sb.standings(players);
  const res = sb.resolveCut(doneArr, 2, '최종 코스 카운트백');
  assert.equal(res.autoResolved, true);
  assert.deepEqual(res.advanced.map(p => p.name).sort(), ['A', 'B']);
});

test('컷 동점 자동 해소 — 연장자 우선', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 1; sb.coursePars = evenPars(66, 1);
  const players = [
    player('A', { age: 50, scores: flatScores([66]) }),
    player('B', { age: 65, scores: flatScores([66]) }), // 동타, 나이 많음 → 우선
    player('C', { age: 40, scores: flatScores([70]) }),
  ];
  const doneArr = sb.standings(players);
  const res = sb.resolveCut(doneArr, 2, '연장자 우선');
  assert.equal(res.autoResolved, true);
  assert.ok(res.advanced.map(p => p.name).includes('B'));
});

test('컷 동점 자동 해소 불가 — 연장전(서든데스)/별도선정은 수동 선택으로 넘김', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 1; sb.coursePars = evenPars(66, 1);
  // A는 확정 1위, B/C가 마지막 진출 자리(2번째)를 두고 동타 — 컷 "경계"의 동점만
  // 수동 처리 대상이어야 한다(1·2위끼리의 내부 동순위는 해소 불필요).
  const players = [
    player('A', { scores: flatScores([60]) }),
    player('B', { scores: flatScores([66]) }),
    player('C', { scores: flatScores([66]) }),
  ];
  const doneArr = sb.standings(players);
  for (const tieRule of ['연장전 (서든데스)', '별도선정 (운영위 결정)']) {
    const res = sb.resolveCut(doneArr, 2, tieRule);
    assert.equal(res.autoResolved, false, tieRule);
    assert.deepEqual(res.base.map(p => p.name), ['A'], tieRule);
    assert.equal(res.tied.length, 2, tieRule);
    assert.deepEqual(res.tied.map(p => p.name).sort(), ['B', 'C'], tieRule);
  }
});

test('사고 재현: 72/72/72 컷 2명 — 3명 전원 동타면 전원 수동 선택 대상(임의 확정 금지)', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 1; sb.coursePars = evenPars(72, 1); // par 72 코스
  const players = [
    player('A', { scores: flatScores([72]) }),
    player('B', { scores: flatScores([72]) }),
    player('C', { scores: flatScores([72]) }),
  ];
  const doneArr = sb.standings(players);
  const res = sb.resolveCut(doneArr, 2, '별도선정 (운영위 결정)');
  assert.equal(res.autoResolved, false);
  assert.equal(res.base.length, 0, '경계 동점이 배열 전체를 덮으면 자동 확정 인원이 있으면 안 됨');
  assert.equal(res.tied.length, 3, '3명 전원이 동점 처리 대상이어야 함');
});

test('사고 재현: 총점만(코스 1개) 동점 — 카운트백 데이터가 없어 자동 해소되면 안 됨', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 1; sb.coursePars = evenPars(72, 1);
  // 총점만 단계는 periodStandings/bestArr 기반 — 코스가 1개면 카운트백 재료가 topar와 동일해
  // "최종 코스 카운트백"을 적용해도 구분이 안 되는 게 정상(자동 해소 절대 금지 케이스).
  const players = [
    { name: 'A', age: 40, st: '', best: { 0: 80 } },
    { name: 'B', age: 40, st: '', best: { 0: 80 } },
  ];
  const doneArr = sb.periodStandings(players);
  const res = sb.resolveCut(doneArr, 1, '최종 코스 카운트백');
  assert.equal(res.autoResolved, false, '단일 코스에서 카운트백은 항상 동률 — 자동 해소돼선 안 됨');
});

test('기간형 베스트 합산 — 갱신(더 낮은 타수로 교체)', () => {
  const sb = loadAggregation();
  const plRows = [
    { player_id: 'p1', course_no: 0, strokes_total: 85 },
    { player_id: 'p1', course_no: 0, strokes_total: 78 }, // 더 좋은 기록 → 갱신
  ];
  const bestMap = sb.computeBestMap(plRows);
  assert.equal(bestMap.p1[0], 78);
});

test('기간형 베스트 합산 — 유지(더 나쁜 재도전은 무시)', () => {
  const sb = loadAggregation();
  const plRows = [
    { player_id: 'p1', course_no: 0, strokes_total: 78 },
    { player_id: 'p1', course_no: 0, strokes_total: 85 }, // 더 나쁜 기록 → 무시
  ];
  const bestMap = sb.computeBestMap(plRows);
  assert.equal(bestMap.p1[0], 78, '베스트가 나쁜 재도전에 덮어써지면 안 됨');
});

test('기간형 순위(periodStandings) — tot은 전 코스 완주해야 확정, 순위 자체는 실시간 페이스로 매김', () => {
  const sb = loadAggregation();
  sb.ROUNDS = 2; sb.coursePars = evenPars(66, 2);
  // 진행 중인 라이브 리더보드 특성상, 아직 다 안 돈 선수도 지금까지 페이스로
  // 순위에 함께 노출된다(실제 골프 리더보드의 "thru" 표시와 동일한 설계) —
  // 완주 여부는 tot(null 여부)로만 구분하고, 정렬 자체를 완주자 우선으로 막지 않는다.
  // 단, 한 코스도 안 친 선수(completed===0)는 항상 맨 뒤로 밀린다.
  const players = [
    { name: 'A', age: 40, st: '', best: { 0: 65, 1: 65 } },  // 완주, 합 130, topar -2
    { name: 'B', age: 40, st: '', best: { 0: 60 } },         // 1코스만, topar -6(더 좋은 페이스)
    { name: 'C', age: 40, st: '', best: {} },                // 미출전
  ];
  const res = sb.periodStandings(players);
  assert.deepEqual(res.map(r => r.p.name), ['B', 'A', 'C'], '페이스 좋은 진행 중 선수가 위, 미출전은 항상 맨 뒤');
  assert.equal(res.find(r => r.p.name === 'A').tot, 130);
  assert.equal(res.find(r => r.p.name === 'B').tot, null, '미완주는 tot 확정 전이어야 함');
});
