#!/usr/bin/env bash
# 기준서 5-3b(강화) — 운영(nuga1.vercel.app) 배포 스크립트.
#
# 리허설2 스크립트와 같은 검문을 걸되 대상만 운영이다. 손으로 `vercel --prod`를
# 치지 않는다 — 오배포 사고 두 번이 전부 수동 타이핑에서 났다.
#
# 이 스크립트는 master 브랜치에서만 돈다. 미병합 작업 브랜치가 운영에 나가는 것을
# 막는 게 첫 번째 검문이다.
#
# 사용법:  bash scripts/deploy-production.sh

set -euo pipefail

SRC_DIR="/c/Users/mudae/OneDrive/바탕 화면/nuga1"
EXPECT_BRANCH="master"
EXPECT_PROJECT="nuga1"
EXPECT_ALIAS="https://nuga1.vercel.app"

fail(){ echo "❌ $*" >&2; exit 1; }

cd "$SRC_DIR"

# ── 1. master 브랜치이고, 커밋 안 된 변경이 없어야 한다 ──
BR=$(git branch --show-current)
[ "$BR" = "$EXPECT_BRANCH" ] || fail "현재 브랜치가 $BR 다 — 운영 배포는 $EXPECT_BRANCH 에서만"
[ -z "$(git status --porcelain index.html)" ] || fail "index.html 에 커밋 안 된 변경이 있다 — 커밋 후 다시"

# ── 2. 프로젝트 연결 확인 ──
PROJ_FILE=".vercel/project.json"
[ -f "$PROJ_FILE" ] || fail "$PROJ_FILE 없음"
grep -q "\"projectName\":\"$EXPECT_PROJECT\"" "$PROJ_FILE" \
  || fail "프로젝트 불일치 — $PROJ_FILE 이 $EXPECT_PROJECT 가 아니다"

SRC_MD5=$(md5sum index.html | cut -d' ' -f1)
echo "· 브랜치 $BR / $(git log --oneline -1)"
echo "· 소스 md5 ${SRC_MD5:0:12} ($(wc -c < index.html) bytes)"

# ── 3. 배포 ──
OUT=$(vercel deploy --yes --prod 2>&1) || { echo "$OUT" >&2; fail "vercel deploy 실패"; }
URL=$(printf '%s' "$OUT" | grep -oE 'https://[a-z0-9.-]+\.vercel\.app' | tail -1)
[ -n "$URL" ] || { echo "$OUT" >&2; fail "배포 URL을 읽지 못했다"; }
echo "· 배포됨: $URL"

# ── 4. 실제로 운영 도메인에 그 내용이 올라갔는지 본문 대조 ──
#    (배포 URL 자체는 보호 리다이렉트를 주므로 별칭 도메인 본문으로 판정한다)
sleep 3
LIVE=$(mktemp); curl -sL "$EXPECT_ALIAS/" -o "$LIVE"
LIVE_MD5=$(md5sum "$LIVE" | cut -d' ' -f1)
LIVE_SIZE=$(wc -c < "$LIVE")
CNS=$(grep -c 'cnsUtilBarHTML' "$LIVE" || true)
rm -f "$LIVE"
echo "· $EXPECT_ALIAS : ${LIVE_SIZE} bytes / md5 ${LIVE_MD5:0:12} / 콘솔 마커 ${CNS}건"

[ "$LIVE_MD5" = "$SRC_MD5" ] \
  || fail "운영 도메인 본문이 소스와 다르다 (엣지 캐시일 수 있으니 1분 뒤 재확인)"
echo "✅ 운영 배포·대조 완료 — $EXPECT_ALIAS 본문이 $BR 소스와 일치"
echo "   롤백이 필요하면: vercel ls nuga1 --environment production 으로 직전 배포를 찾아 promote"
