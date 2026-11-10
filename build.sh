#!/usr/bin/env bash
# Build Knowl's Mattermost from source: the open-source edition at the pinned tag, Knowl's
# patches, the mechanical transform, then a local image. docs/guides/agent-workspace-design.md,
# The pieces.
#
#   dashboard/agent/mattermost/build.sh            build the image knowl-mattermost:<tag>-knowl
#   dashboard/agent/mattermost/build.sh --patches  rewrite patches/ from the source's knowl branch
#
# To change a patch: edit on the source's `knowl` branch (one commit per patch), then
# --patches. A build leaves the source back on that branch, clean.
#
# The source lives outside this repository (KNOWL_MATTERMOST_SRC, default
# ~/.knowable/agent/mattermost-src). Nothing under server/enterprise (Mattermost Source
# Available License) is built: it is deleted before compiling, so linking it fails.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TAG="$(cat "$HERE/VERSION")"
SRC="${KNOWL_MATTERMOST_SRC:-$HOME/.knowable/agent/mattermost-src}"
DIST="${KNOWL_MATTERMOST_DIST:-$HOME/.knowable/agent/mattermost-dist}"
IMAGE="${KNOWL_MATTERMOST_IMAGE:-knowl-mattermost:${TAG#v}-knowl}"
# KNOWL_MATTERMOST_ARCH builds for another architecture than the Docker host's: the local
# development stack runs linux/amd64 (orchestrator/dev/workspace_stack.py).
ARCH="${KNOWL_MATTERMOST_ARCH:-$(docker version --format '{{.Server.Arch}}')}"

if [ "${1:-}" = "--patches" ]; then
  rm -f "$HERE"/patches/*.patch
  git -C "$SRC" format-patch -q --no-signature --zero-commit -o "$HERE/patches" "$TAG..knowl"
  ls "$HERE/patches"
  exit 0
fi

if [ ! -d "$SRC/.git" ]; then
  git clone -q --depth 1 --branch "$TAG" https://github.com/mattermost/mattermost.git "$SRC"
fi
cd "$SRC"
git fetch -q --depth 1 origin tag "$TAG" 2>/dev/null || true
# A clean tree at the tag, keeping ignored files (node_modules) for speed.
git checkout -q -f "$TAG"
git clean -fdq
git switch -q -C knowl-build
export GIT_COMMITTER_NAME="Knowable Labs" GIT_COMMITTER_EMAIL="knowl@knowl.invalid"
git am -q "$HERE"/patches/*.patch

find server/enterprise -mindepth 1 ! -name placeholder.go -exec rm -rf {} + 2>/dev/null || true
node "$HERE/transform.mjs" "$SRC"

echo "== webapp"
(cd webapp && { [ -d node_modules ] || npm ci --no-audit --no-fund --loglevel=error; } && npm run build)

echo "== server (linux/$ARCH)"
HASH="$(git rev-parse HEAD)"
LDFLAGS="-X github.com/mattermost/mattermost/server/public/model.BuildNumber=${TAG#v}-knowl"
LDFLAGS+=" -X 'github.com/mattermost/mattermost/server/public/model.BuildDate=$(date -u)'"
LDFLAGS+=" -X github.com/mattermost/mattermost/server/public/model.BuildHash=$HASH"
LDFLAGS+=" -X github.com/mattermost/mattermost/server/public/model.BuildHashEnterprise=none"
LDFLAGS+=" -X github.com/mattermost/mattermost/server/public/model.BuildEnterpriseReady=false"
rm -rf "$DIST" && mkdir -p "$DIST/bin" "$DIST/config" "$DIST/logs" "$DIST/data" "$DIST/plugins" "$DIST/client/plugins"
(
  cd server
  rm -f go.work go.work.sum && go work init && go work use . && go work use ./public
  CGO_ENABLED=0 GOOS=linux GOARCH="$ARCH" go build -trimpath -tags production -ldflags "$LDFLAGS" -o "$DIST/bin/" ./cmd/mattermost ./cmd/mmctl
  OUTPUT_CONFIG="$DIST/config/config.json" go run ./scripts/config_generator
  cp -RL fonts templates i18n "$DIST/"
  rm -rf "$DIST"/templates/*.mjml "$DIST/templates/partials/"
)
cp -RL webapp/channels/dist/* "$DIST/client/"
cp LICENSE.txt NOTICE.txt "$DIST/"
cat > "$DIST/SOURCE.md" <<NOTE
Knowl's build of Mattermost ${TAG}, open-source edition (AGPLv3; admin tools and configuration
Apache 2.0). Source: https://github.com/mattermost/mattermost at ${TAG}, with the patches and
transform in knowablelabs' dashboard/agent/mattermost/ applied. server/enterprise is not built.
NOTE

echo "== image $IMAGE"
cp "$HERE/Dockerfile" "$DIST/Dockerfile"
docker build -q --platform "linux/$ARCH" -t "$IMAGE" "$DIST"

# The candidate producer retains the exact transformed source before cleanup,
# including the pinned module/lock files. No customer data or controller state is
# part of this fresh source tree. Local distribution plan §9 and §12.
if [ -n "${KNOWL_MATTERMOST_SOURCE_ARCHIVE:-}" ]; then
  tar -czf "$KNOWL_MATTERMOST_SOURCE_ARCHIVE" \
    --exclude='./.git' --exclude='node_modules' --exclude='./server/bin' \
    --exclude='./webapp/channels/dist' .
fi

# Back to the editing branch, without the build's deletions and transform.
git checkout -q -f knowl 2>/dev/null || true
git clean -fdq
echo "built $IMAGE"
