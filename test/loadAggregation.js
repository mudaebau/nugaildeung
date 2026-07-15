// 집계 로직(순위·컷·동점·기간형 베스트)을 index.html에서 "그대로" 추출해 격리 실행한다.
// 재구현 금지 원칙 — 여기서 로직을 다시 옮겨 적지 않고, 실제 프로덕션 소스 텍스트를
// 라인 범위로 잘라 vm 샌드박스에서 평가한다. index.html의 해당 함수가 바뀌면 이 테스트도
// 항상 "지금 배포되는 코드"를 검사하게 된다(별도 사본이 아니라서 드리프트가 없음).
//
// 주의: 아래 라인 범위가 index.html 리팩터링으로 바뀌면 이 로더도 같이 갱신해야 한다.
// extractBlock이 각 블록의 첫 줄 텍스트로 자체 검증하므로, 범위가 어긋나면 즉시 에러로 드러난다.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function extractBlock(lines, startLine, endLine, mustStartWith) {
  // startLine/endLine: 1-based, index.html의 실제 줄 번호(그대로 복붙 가능하도록)
  const slice = lines.slice(startLine - 1, endLine);
  if (!slice[0].trimStart().startsWith(mustStartWith)) {
    throw new Error(
      `aggregation loader: index.html:${startLine}이 더 이상 "${mustStartWith}"로 시작하지 않습니다 — ` +
      `함수가 이동했으니 test/loadAggregation.js의 라인 범위를 갱신하세요. 실제 내용: ${slice[0].slice(0, 80)}`
    );
  }
  return slice.join('\n');
}

function loadAggregation() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const lines = html.split('\n');

  // 기간형 "베스트 합산"(재도전 시 더 낮은 타수만 반영)은 별도 named 함수가 아니라
  // loadBoardData 등 3곳에 반복되는 인라인 forEach다(index.html:2450-2451 등, 동일 텍스트).
  // 로직 자체(최소값 갱신 조건문)는 그대로 재사용하고, 호출 가능한 함수로만 감싼다.
  const bestMapBody = extractBlock(lines, 2450, 2451, 'const bestMap={}');
  const computeBestMapFn = `function computeBestMap(plRows){\n${bestMapBody}\nreturn bestMap}`;

  const src = [
    extractBlock(lines, 1593, 1600, 'const PRESET66'),           // PRESET66/54, coursePars, parAt, courseParTotal, isOut
    extractBlock(lines, 2227, 2275, 'function cutCompetitors'),  // cutCompetitors ~ resolveCut(+courseSeries/courseCompare/ageCompare/tieGroupAt)
    extractBlock(lines, 4783, 4801, 'function sums'),            // sums, standings
    extractBlock(lines, 4978, 5003, 'function periodStandings'), // periodStandings
    computeBestMapFn,
  ].join('\n\n');

  const sandbox = { ROUNDS: 2, coursePars: [], players: [] };
  vm.createContext(sandbox);
  try {
    vm.runInContext(src, sandbox, { filename: 'index.html (extracted)' });
  } catch (e) {
    throw new Error(`aggregation loader: 추출한 소스 평가 실패 — index.html 구조가 바뀌었을 수 있습니다.\n${e.message}`);
  }
  return sandbox;
}

module.exports = { loadAggregation };
