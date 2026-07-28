#!/usr/bin/env bash
# 기준서 5-3b(강화) — 리허설2 전용 배포 스크립트.
#
# 왜 이 파일이 있나: `cd /c/tmp/nuga1-rehearsal2`를 빠뜨린 수동 배포로
# 운영 프로젝트에 배포가 나간 사고가 두 번 났다. 사람의 주의가 아니라
# 구조로 막는다 — 디렉터리·프로젝트를 여기 하드코딩하고, 배포 후
# Aliased 도메인을 실제로 대조해 다르면 실패(exit 1)로 끝낸다.
#
# 사용법:  bash scripts/deploy-rehearsal2.sh
# 운영(nuga1.vercel.app) 배포는 이 스크립트로 할 수 없다 — 의도적으로.

set -euo pipefail

SRC_DIR="/c/Users/mudae/OneDrive/바탕 화면/nuga1"
DEPLOY_DIR="/c/tmp/nuga1-rehearsal2"
EXPECT_PROJECT="nuga1-rehearsal2"
EXPECT_ALIAS="https://nuga1-rehearsal2.vercel.app"
FORBIDDEN_ALIAS="nuga1.vercel.app"   # 운영 도메인 — 결과에 나오면 무조건 실패

fail(){ echo "❌ $*" >&2; exit 1; }

# ── 1. 배포 디렉터리가 정말 리허설2 프로젝트인지 확인 ──
[ -d "$DEPLOY_DIR" ] || fail "배포 디렉터리 없음: $DEPLOY_DIR"
PROJ_FILE="$DEPLOY_DIR/.vercel/project.json"
[ -f "$PROJ_FILE" ] || fail "$PROJ_FILE 없음 — 이 디렉터리는 vercel 프로젝트에 연결돼 있지 않다"
grep -q "\"projectName\":\"$EXPECT_PROJECT\"" "$PROJ_FILE" \
  || fail "프로젝트 불일치 — $PROJ_FILE 가 $EXPECT_PROJECT 가 아니다. 운영에 쏠 뻔했다."

# ── 2. 소스 복사 ──
[ -f "$SRC_DIR/index.html" ] || fail "소스 없음: $SRC_DIR/index.html"
cp "$SRC_DIR/index.html" "$DEPLOY_DIR/index.html"
SRC_MD5=$(md5sum "$SRC_DIR/index.html" | cut -d' ' -f1)
echo "· 소스 복사 완료 (md5 ${SRC_MD5:0:12}, $(wc -c < "$SRC_DIR/index.html") bytes)"

# ── 3. 배포 (반드시 배포 디렉터리 안에서) ──
cd "$DEPLOY_DIR"
OUT=$(vercel deploy --yes --prod 2>&1) || { echo "$OUT" >&2; fail "vercel deploy 실패"; }
URL=$(printf '%s' "$OUT" | grep -oE 'https://[a-z0-9.-]+\.vercel\.app' | tail -1)
[ -n "$URL" ] || { echo "$OUT" >&2; fail "배포 URL을 읽지 못했다"; }
echo "· 배포됨: $URL"

case "$URL" in
  https://$EXPECT_PROJECT-*) ;;
  *) fail "배포 URL이 $EXPECT_PROJECT 프로젝트가 아니다: $URL" ;;
esac

# ── 4. Aliased 자동 대조 — 여기서 걸러야 사고가 안 난다 ──
ALIASES=$(vercel inspect "$URL" 2>&1 | grep -oE 'https://[a-z0-9.-]+\.vercel\.app' || true)
echo "· Aliased:"; printf '%s\n' "$ALIASES" | sed 's/^/    /'

printf '%s\n' "$ALIASES" | grep -qx "$EXPECT_ALIAS" \
  || fail "Aliased 에 $EXPECT_ALIAS 가 없다 — 의도한 대상이 아니다"
printf '%s\n' "$ALIASES" | grep -qx "https://$FORBIDDEN_ALIAS" \
  && fail "운영 도메인($FORBIDDEN_ALIAS)이 Aliased 에 있다 — 즉시 확인 필요"

# ── 5. 실제로 그 내용이 올라갔는지 본문 대조 ──
LIVE=$(mktemp); curl -sL "$EXPECT_ALIAS/" -o "$LIVE"
LIVE_MD5=$(md5sum "$LIVE" | cut -d' ' -f1); rm -f "$LIVE"
if [ "$LIVE_MD5" = "$SRC_MD5" ]; then
  echo "✅ 리허설2 배포·대조 완료 — $EXPECT_ALIAS 본문이 소스와 일치"
else
  echo "⚠ $EXPECT_ALIAS 본문 md5(${LIVE_MD5:0:12})가 소스(${SRC_MD5:0:12})와 다르다 — 엣지 캐시일 수 있으니 재확인" >&2
  exit 1
fi
