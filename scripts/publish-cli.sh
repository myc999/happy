#!/usr/bin/env bash
# 发布 @aif4/aif4 到 npm
# 用法:
#   ./scripts/publish-cli.sh beta    # 发布 beta 版，自动递增 beta 号 (e.g. beta.13 -> beta.14)
#   ./scripts/publish-cli.sh 1.2.0   # 发布指定正式版本
#
# 注意: @aif4/happy-wire 已 bundle 进 CLI，无需单独发布

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_DIR="$REPO_ROOT/packages/happy-cli"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[publish]${NC} $1"; }
warn() { echo -e "${YELLOW}[publish]${NC} $1"; }
die()  { echo -e "${RED}[publish] ERROR:${NC} $1"; exit 1; }

VERSION_ARG="${1:-}"
[[ -z "$VERSION_ARG" ]] && die "请指定版本，例如: $0 beta 或 $0 1.2.0"

# 检查 npm token
if ! grep -q "registry.npmjs.org/:_authToken" ~/.npmrc 2>/dev/null; then
  die "~/.npmrc 中没有 npm token，请先运行:\n  echo '//registry.npmjs.org/:_authToken=你的token' >> ~/.npmrc"
fi

# ── 处理 CLI 版本号 ─────────────────────────────────────────────────
cd "$CLI_DIR"
CURRENT=$(node -p "require('./package.json').version")
log "当前 CLI 版本: $CURRENT"

if [[ "$VERSION_ARG" == "beta" ]]; then
  # 从当前版本自动递增 beta 号
  # e.g. 1.1.10-beta.11 -> 1.1.10-beta.12
  if [[ "$CURRENT" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-beta\.([0-9]+)$ ]]; then
    BASE="${BASH_REMATCH[1]}"
    NUM="${BASH_REMATCH[2]}"
    NEW_VERSION="${BASE}-beta.$((NUM + 1))"
  else
    # 当前不是 beta 版，在当前版本基础上加 -beta.1
    NEW_VERSION="${CURRENT}-beta.1"
  fi
  TAG="beta"
else
  NEW_VERSION="$VERSION_ARG"
  # 正式版不带 tag，或自动判断是否是 prerelease
  if [[ "$NEW_VERSION" =~ - ]]; then
    TAG="beta"
  else
    TAG="latest"
  fi
fi

log "新版本: $NEW_VERSION (tag: $TAG)"

# 写入新版本号
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.version = '$NEW_VERSION';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"

# ── 构建 + 测试 + 发布 ───────────────────────────────────────────────
log "构建中..."
pnpm run build

log "跑单元测试..."
pnpm vitest run --project unit

log "发布 @aif4/aif4@$NEW_VERSION..."
pnpm publish --access public --no-git-checks --tag "$TAG"

# ── 提交版本号变更 ────────────────────────────────────────────────────
cd "$REPO_ROOT"
git add packages/happy-cli/package.json
git commit -m "chore: bump @aif4/aif4 to $NEW_VERSION"
log "已提交版本号变更"

log "✅ 发布完成！"
echo ""
echo "  安装命令:"
if [[ "$TAG" == "beta" ]]; then
  echo "    npm install -g @aif4/aif4@beta"
else
  echo "    npm install -g @aif4/aif4"
fi
