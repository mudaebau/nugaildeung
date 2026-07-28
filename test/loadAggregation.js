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

// 시작·끝을 "마커 텍스트"로 찾는다. 예전엔 라인 번호를 박아뒀는데, index.html을 한 줄만
// 고쳐도 범위가 밀려 12개 테스트가 통째로 깨졌다(네 번 반복됨). 이제 위아래로 코드가
// 들어와도 블록만 정확히 잘라낸다 — 추출 대상은 여전히 프로덕션 소스 원문 그대로다.
function extractBlock(lines, startsWith, endsBefore) {
  const from = lines.findIndex(l => l.trimStart().startsWith(startsWith));
  if (from < 0) {
    throw new Error(
      `aggregation loader: index.html에서 "${startsWith}"로 시작하는 줄을 찾지 못했습니다 — ` +
      `함수 이름이 바뀌었는지 확인하세요.`
    );
  }
  const rest = lines.slice(from + 1);
  const rel = rest.findIndex(l => l.trimStart().startsWith(endsBefore));
  if (rel < 0) {
    throw new Error(
      `aggregation loader: "${startsWith}" 이후에 끝 마커 "${endsBefore}"가 없습니다 — ` +
      `블록 경계를 다시 지정하세요.`
    );
  }
  return lines.slice(from, from + 1 + rel).join('\n');
}

function loadAggregation() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const lines = html.split('\n');

  // 기간형 "베스트 합산"(재도전 시 더 낮은 타수만 반영)은 별도 named 함수가 아니라
  // loadBoardData 등 3곳에 반복되는 인라인 forEach다(index.html:2657-2658 등, 동일 텍스트).
  // 로직 자체(최소값 갱신 조건문)는 그대로 재사용하고, 호출 가능한 함수로만 감싼다.
  const bestMapBody = extractBlock(lines, 'const bestMap={}', 'ROUNDS=');
  const computeBestMapFn = `function computeBestMap(plRows){\n${bestMapBody}\nreturn bestMap}`;

  const src = [
    extractBlock(lines, 'const PRESET66', 'let jRound='),                    // PRESET66/54, coursePars, parAt, courseParTotal, isOut
    extractBlock(lines, 'function cutCompetitors', 'async function renderOpsStats'), // cutCompetitors ~ resolveCut(+tieGroupAt 등)
    extractBlock(lines, 'function sums', 'async function submitBoardGate'), // sums, standings
    extractBlock(lines, 'function periodStandings', 'function renderPeriodBoard'), // periodStandings (P70 완주자 우선 정렬 포함)
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
