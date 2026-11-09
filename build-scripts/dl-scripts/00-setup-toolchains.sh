#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once

for cmd in \
  docker git python3 cmake ninja zip unzip readelf adb curl sha256sum \
  dpkg-deb patchelf file nm nproc tar; do
  require_cmd "$cmd"
done
if [ ! -d "$TERMUX_PACKAGES_DIR/.git" ]; then
  log "termux-packages checkout is absent or invalid; resetting builder container $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  log "Cloning termux-packages at pinned commit $TERMUX_PACKAGES_COMMIT into $TERMUX_PACKAGES_DIR"
  rm -rf "$TERMUX_PACKAGES_DIR"
  git clone --no-checkout --depth 1 https://github.com/termux/termux-packages.git "$TERMUX_PACKAGES_DIR"
fi
git -C "$TERMUX_PACKAGES_DIR" fetch --depth 1 origin "$TERMUX_PACKAGES_COMMIT"
git -C "$TERMUX_PACKAGES_DIR" checkout --force --detach "$TERMUX_PACKAGES_COMMIT"
git -C "$TERMUX_PACKAGES_DIR" reset --hard "$TERMUX_PACKAGES_COMMIT"


rm -rf \
  "$TERMUX_PACKAGES_DIR/packages/python-cffi-android" \
  "$TERMUX_PACKAGES_DIR/packages/python-curl-cffi-android" \
  "$TERMUX_PACKAGES_DIR/packages/aria2-next"

"$SCRIPT_DIR/apply-termux-patches.sh" "$TERMUX_PACKAGES_DIR"
[ "$(git -C "$TERMUX_PACKAGES_DIR" rev-parse HEAD)" = "$TERMUX_PACKAGES_COMMIT" ] \
  || die "termux-packages checkout does not match pinned commit $TERMUX_PACKAGES_COMMIT"

require_cmd python3
require_cmd cmake
require_cmd ninja
require_cmd zip
require_cmd unzip
require_cmd readelf
require_cmd adb





require_file "$TERMUX_JAVA_HOME/bin/java" "host JDK java executable"
JAVA_VERSION="$("$TERMUX_JAVA_HOME/bin/java" -version 2>&1 | head -n1)"
log "Host JDK ready at $TERMUX_JAVA_HOME ($JAVA_VERSION)"


if [ ! -d "$TERMUX_NDK_ROOT" ]; then
  log "Running termux-packages' own Android SDK/NDK setup script"
  (
    cd "$TERMUX_PACKAGES_DIR"
    
    
    for attempt in 1 2 3; do
      if ANDROID_HOME="$ANDROID_SDK_ROOT" NDK="$TERMUX_NDK_ROOT" ./scripts/setup-android-sdk.sh; then
        break
      fi
      warn "setup-android-sdk.sh failed (attempt $attempt/3), retrying"
      [ "$attempt" -eq 3 ] && die "setup-android-sdk.sh did not succeed after 3 attempts"
    done
  )
fi
require_dir "$TERMUX_NDK_ROOT" "expected host NDK after setup-android-sdk.sh"
require_file "$TERMUX_NDK_ROOT/source.properties" "NDK provenance metadata"
NDK_REVISION="$(sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' "$TERMUX_NDK_ROOT/source.properties" | head -1)"
[ "$NDK_REVISION" = "$TERMUX_NDK_REVISION" ] \
  || die "NDK revision mismatch: expected $TERMUX_NDK_REVISION, found ${NDK_REVISION:-unknown} at $TERMUX_NDK_ROOT"
log "Termux NDK ready at $TERMUX_NDK_ROOT (Pkg.Revision=$NDK_REVISION)"





if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  NDK_MOUNT_SOURCE="$(docker container inspect "$CONTAINER_NAME" \
    --format "{{range .Mounts}}{{if eq .Destination \"$TERMUX_NDK_CONTAINER_ROOT\"}}{{.Source}}{{end}}{{end}}" 2>/dev/null || true)"
  if [ "$NDK_MOUNT_SOURCE" != "$TERMUX_NDK_ROOT" ]; then
    log "Builder container NDK mount is absent/stale; resetting $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  else
    log "Builder container NDK mount verified: $TERMUX_NDK_ROOT -> $TERMUX_NDK_CONTAINER_ROOT"
  fi
fi



if [ ! -d "$ANDROID_SDK_ROOT" ]; then
  warn "ANDROID_SDK_ROOT ($ANDROID_SDK_ROOT) not found."
  warn "curl-impersonate/quickjs-ng builds below use \$TERMUX_NDK_ROOT directly"
  warn "via -DCMAKE_TOOLCHAIN_FILE, so a separate Android Studio SDK install"
  warn "is optional as long as the NDK toolchain files under TERMUX_NDK_ROOT exist."
fi


INSTALLED_CIBW_VERSION="$(python3 -c 'import importlib.metadata as m; print(m.version("cibuildwheel"))' 2>/dev/null || true)"
if [ "$INSTALLED_CIBW_VERSION" != "$CIBUILDWHEEL_VERSION" ]; then
  log "Installing pinned cibuildwheel==$CIBUILDWHEEL_VERSION (found ${INSTALLED_CIBW_VERSION:-none})"
  python3 -m pip install --user --break-system-packages "cibuildwheel==$CIBUILDWHEEL_VERSION" \
    || python3 -m pip install --user "cibuildwheel==$CIBUILDWHEEL_VERSION"
fi
INSTALLED_CIBW_VERSION="$(python3 -c 'import importlib.metadata as m; print(m.version("cibuildwheel"))')"
[ "$INSTALLED_CIBW_VERSION" = "$CIBUILDWHEEL_VERSION" ] \
  || die "cibuildwheel version mismatch: expected $CIBUILDWHEEL_VERSION, found $INSTALLED_CIBW_VERSION"
log "cibuildwheel pinned: $INSTALLED_CIBW_VERSION"

if ! python3 -c 'import wheel' >/dev/null 2>&1; then
  log "Installing the host wheel module used to repair CFFI wheels"
  python3 -m pip install --user --break-system-packages wheel \
    || python3 -m pip install --user wheel
fi
python3 -c 'import wheel' \
  || die "the host Python wheel module is required by stage 20"

log "Ensuring pinned Termux builder image is present: $TERMUX_BUILDER_IMAGE_NAME"
docker pull "$TERMUX_BUILDER_IMAGE_NAME"
RESOLVED_BUILDER_DIGEST="$(docker image inspect "$TERMUX_BUILDER_IMAGE_NAME" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
log "Termux builder resolved image: ${RESOLVED_BUILDER_DIGEST:-$TERMUX_BUILDER_IMAGE_NAME}"


PROVENANCE_FILE="$OUT_DIR/build-provenance.env"
{
  printf 'TERMUX_PACKAGES_COMMIT=%s\n' "$TERMUX_PACKAGES_COMMIT"
  printf 'CURL_IMPERSONATE_COMMIT=%s\n' "$CURL_IMPERSONATE_COMMIT"
  printf 'CURL_CFFI_COMMIT=%s\n' "$CURL_CFFI_COMMIT"
  printf 'QUICKJS_NG_COMMIT=%s\n' "$QUICKJS_NG_COMMIT"
  printf 'FFMPEG_MAKER_COMMIT=%s\n' "$FFMPEG_MAKER_COMMIT"
  printf 'ARIA2_NEXT_COMMIT=%s\n' "$ARIA2_NEXT_COMMIT"
  printf 'TERMUX_PYTHON_VERSION=%s\n' "$(python_full_version)"
  printf 'TERMUX_BUILDER_IMAGE_NAME=%s\n' "$TERMUX_BUILDER_IMAGE_NAME"
  printf 'CONTAINER_NAME=%s\n' "$CONTAINER_NAME"
  printf 'ANDROID_NDK_REVISION=%s\n' "$NDK_REVISION"
  printf 'TERMUX_JAVA_HOME=%s\n' "$TERMUX_JAVA_HOME"
  printf 'JAVA_VERSION=%s\n' "$JAVA_VERSION"
  printf 'TERMUX_NDK_HOST_ROOT=%s\n' "$TERMUX_NDK_ROOT"
  printf 'TERMUX_NDK_CONTAINER_ROOT=%s\n' "$TERMUX_NDK_CONTAINER_ROOT"
  printf 'CIBUILDWHEEL_VERSION=%s\n' "$INSTALLED_CIBW_VERSION"
  printf 'CERTIFI_VERSION=%s\n' "$CERTIFI_VERSION"
  printf 'CMAKE_VERSION=%s\n' "$(cmake --version | head -1)"
  printf 'NINJA_VERSION=%s\n' "$(ninja --version)"
  printf 'PYTHON_VERSION=%s\n' "$(python3 --version 2>&1)"
  printf 'DOCKER_VERSION=%s\n' "$(docker --version)"
  printf 'GIT_VERSION=%s\n' "$(git --version)"
} > "$PROVENANCE_FILE"
log "Wrote build provenance: $PROVENANCE_FILE"

log "Toolchain setup complete."
