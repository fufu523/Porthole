#!/bin/bash
# Stage app/RuntimeStage from the UPSTREAM OFFICIAL RELEASE IPA instead of
# building the Madeira runtime from source.
#
# Why: app/project.yml references 14 folder/file resources under
# app/RuntimeStage/Resources/ (plus the static-lib folder
# app/RuntimeStage/lib). Without them `xcodegen generate` fails before any
# compilation happens. Building them the upstream way (docs/SOURCE.md:
# patch + build Wine/FEX/DXMT/FFmpeg/... for hours, then
# tools/stage_runtime.sh) has never been verified on a clean machine —
# upstream says so itself — and is impractical on a stock CI runner.
#
# The official release IPA for the SAME version as this source tree
# (tag v<MARKETING_VERSION>, build <CURRENT_PROJECT_VERSION>) already
# contains every one of those resources, because folder references are
# copied verbatim into Porthole.app. This script downloads that IPA,
# verifies it against the release's own .sha256 asset, extracts it, and
# copies the resources into app/RuntimeStage/Resources/.
#
# Honest trade-offs (read before trusting the result):
#  - The staged runtime binaries are upstream's official build of the
#    exact same version (1.3.1 / build 928 at time of writing). The app
#    itself is still compiled from this repository's sources; only the
#    prebuilt runtime payload is reused. Porthole and Madeira are
#    GPL-3.0; the corresponding source is this repo + the pinned
#    vendor/Madeira submodule.
#  - RuntimeStage/lib/*.a CANNOT come from an IPA (static libraries are
#    linked into the official executable, not shipped as files). This
#    script copies whatever lib*.a are tracked in the Madeira snapshot
#    (vendor/Madeira/app/Madeira) so the folder exists; the remaining
#    archives (-lntdll_unix, -lwin32u_unix, -lwineserver, -ldxmt_combined,
#    -lavcodec, ...) are products of the from-source build and will be
#    missing at link time unless that build is run. See REPORT3.md.
#  - x86_64-vcruntime is EMPTY in the official IPA on purpose: upstream
#    does not bundle Microsoft's VC runtime (the app downloads it from
#    Microsoft on device, docs/SOURCE.md). An empty folder is what the
#    official build ships, and it satisfies the folder reference.
#
# Usage:
#   .github/scripts/stage_from_release_ipa.sh [path-to-local-ipa]
# With no argument the IPA is downloaded from the GitHub release whose
# tag matches app/project.yml. Env overrides: RELEASE_TAG, IPA_ASSET,
# STAGE_ROOT (default: app/RuntimeStage), MADEIRA_APP (default:
# vendor/Madeira/app/Madeira).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_YML="$REPO_ROOT/app/project.yml"
STAGE_ROOT="${STAGE_ROOT:-$REPO_ROOT/app/RuntimeStage}"
MADEIRA_APP="${MADEIRA_APP:-$REPO_ROOT/vendor/Madeira/app/Madeira}"
UPSTREAM_REPO="tylerkaska112/Porthole"

# The 14 items app/project.yml expects under RuntimeStage/Resources/.
RESOURCE_ITEMS="
nls
aarch64-windows
arm64ec-windows
x86_64-vcruntime
legal
licenses
i386-windows
d3d12
vulkan
gl
compat
prefix-template.tar.gz
cacert.pem
madeira-jit.js
"

version_from_project() { # $1 = key
  grep -E "^[[:space:]]*$1:" "$PROJECT_YML" | head -1 | sed -E 's/.*:[[:space:]]*"?([0-9.]+)"?.*/\1/'
}

LOCAL_IPA="${1:-}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -n "$LOCAL_IPA" ]; then
  IPA="$LOCAL_IPA"
  echo "Using local IPA: $IPA"
  if [ -f "$IPA.sha256" ]; then
    ( cd "$(dirname "$IPA")" && sha256sum -c "$(basename "$IPA").sha256" 2>/dev/null \
      || shasum -a 256 -c "$(basename "$IPA").sha256" )
  fi
else
  MARKETING_VERSION="$(version_from_project MARKETING_VERSION)"
  PROJECT_VERSION="$(version_from_project CURRENT_PROJECT_VERSION)"
  RELEASE_TAG="${RELEASE_TAG:-v$MARKETING_VERSION}"
  IPA_ASSET="${IPA_ASSET:-Porthole-$MARKETING_VERSION-$PROJECT_VERSION.ipa}"
  BASE="https://github.com/$UPSTREAM_REPO/releases/download/$RELEASE_TAG"
  echo "Downloading $IPA_ASSET from upstream release $RELEASE_TAG ..."
  curl -fL --retry 3 -o "$WORK/$IPA_ASSET" "$BASE/$IPA_ASSET"
  curl -fL --retry 3 -o "$WORK/$IPA_ASSET.sha256" "$BASE/$IPA_ASSET.sha256"
  ( cd "$WORK" && (sha256sum -c "$IPA_ASSET.sha256" 2>/dev/null || shasum -a 256 -c "$IPA_ASSET.sha256") )
  IPA="$WORK/$IPA_ASSET"
fi

echo "Extracting IPA ..."
unzip -q -o "$IPA" -d "$WORK/extracted"
APP_DIR="$(find "$WORK/extracted/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
[ -n "$APP_DIR" ] || { echo "ERROR: no .app inside Payload of $IPA"; exit 1; }
echo "Found app bundle: $APP_DIR"

mkdir -p "$STAGE_ROOT/Resources" "$STAGE_ROOT/lib"
missing=0
for item in $RESOURCE_ITEMS; do
  src="$APP_DIR/$item"
  dst="$STAGE_ROOT/Resources/$item"
  if [ -e "$src" ]; then
    rm -rf "$dst"
    cp -R "$src" "$dst"
    echo "staged Resources/$item ($(find "$dst" -type f | wc -l | tr -d ' ') files)"
  elif [ "$item" = "x86_64-vcruntime" ]; then
    # Not in the zip as an entry in some builds; empty is the shipped state.
    mkdir -p "$dst"
    echo "staged Resources/x86_64-vcruntime (empty — upstream ships it empty)"
  else
    echo "ERROR: $item not found in official IPA ($src)"
    missing=1
  fi
done
[ "$missing" -eq 0 ] || { echo "ERROR: staging incomplete"; exit 1; }

# Static libs: only what the Madeira snapshot tracks can be provided here.
if [ -d "$MADEIRA_APP" ]; then
  count=0
  for f in "$MADEIRA_APP"/lib*.a; do
    [ -e "$f" ] || continue
    cp "$f" "$STAGE_ROOT/lib/"
    count=$((count+1))
  done
  echo "staged lib/: $count tracked archive(s) from Madeira snapshot (the rest need the from-source build)"
else
  echo "WARNING: $MADEIRA_APP not found (submodule not checked out?); RuntimeStage/lib left empty"
fi

echo "Done. RuntimeStage now contains:"
ls "$STAGE_ROOT/Resources"
