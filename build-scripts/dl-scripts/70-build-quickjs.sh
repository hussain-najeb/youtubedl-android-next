#!/usr/bin/env bash

















set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once

if [ ! -d "$QUICKJS_DIR/.git" ]; then
  log "Cloning quickjs-ng ($QUICKJS_NG_TAG, pinned $QUICKJS_NG_COMMIT) into $QUICKJS_DIR"
  rm -rf "$QUICKJS_DIR"
  git clone --no-checkout --depth 1 https://github.com/quickjs-ng/quickjs.git "$QUICKJS_DIR"
fi
git -C "$QUICKJS_DIR" fetch --depth 1 origin "$QUICKJS_NG_COMMIT"
git -C "$QUICKJS_DIR" checkout --force --detach "$QUICKJS_NG_COMMIT"
git -C "$QUICKJS_DIR" reset --hard "$QUICKJS_NG_COMMIT"
[ "$(git -C "$QUICKJS_DIR" rev-parse HEAD)" = "$QUICKJS_NG_COMMIT" ] \
  || die "quickjs-ng checkout does not match pinned commit $QUICKJS_NG_COMMIT"

build_quickjs_for_abi() {
  local abi="$1"
  local cmake_abi; cmake_abi="$(abi_cmake_abi "$abi")"
  local build_dir="$WORK_ROOT/quickjs-build-$abi"
  rm -rf "$build_dir"

  log "Configuring QuickJS-ng for $abi (ANDROID_ABI=$cmake_abi)"
  cmake \
    -S "$QUICKJS_DIR" \
    -B "$build_dir" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TERMUX_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$cmake_abi" \
    -DANDROID_PLATFORM="android-$API_LEVEL" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DQJS_BUILD_LIBC=ON

  cmake --build "$build_dir" --parallel "$(nproc)"

  local qjs_bin; qjs_bin="$(find "$build_dir" -maxdepth 2 -name qjs -type f | head -1)"
  local libqjs_so; libqjs_so="$(find "$build_dir" -maxdepth 2 -name 'libqjs.so' | head -1)"
  require_file "$qjs_bin" "qjs executable for $abi"
  require_file "$libqjs_so" "libqjs.so for $abi"

  
  patchelf --set-rpath '$ORIGIN' "$qjs_bin"

  readelf -d "$qjs_bin" | grep -F '$ORIGIN' >/dev/null \
    || die "qjs for $abi has no \$ORIGIN RUNPATH"

  
  
  
  nm -D "$libqjs_so" 2>/dev/null | grep -E ' main$' \
    && warn "libqjs.so unexpectedly exports main() — double-check build output"
  nm -D "$qjs_bin" 2>/dev/null | grep -qE 'JS_NewRuntime|JS_Eval' \
    && warn "qjs binary unexpectedly exports QuickJS API symbols directly — double-check"

  readelf -d "$qjs_bin" | grep -E 'RUNPATH|RPATH' | grep -F '$ORIGIN' >/dev/null \
    || die "qjs executable for $abi has no \$ORIGIN RUNPATH"

  rm -rf "$OUT_DIR/quickjs/$abi"
  mkdir -p "$OUT_DIR/quickjs/$abi"
  cp "$libqjs_so" "$OUT_DIR/quickjs/$abi/libqjs.so"
  cp "$qjs_bin" "$OUT_DIR/quickjs/$abi/libqjs-cli.so"
  log "QuickJS packaged for $abi: libqjs.so (shared lib) + libqjs-cli.so (qjs CLI)"
}

for_each_abi build_quickjs_for_abi

log "Runtime verification (doc section 37) — for each ABI, on-device:"
log "  adb push libqjs.so /data/local/tmp/libqjs.so"
log "  adb push libqjs-cli.so /data/local/tmp/qjs"
log "  adb shell chmod 755 /data/local/tmp/qjs"
log "  adb shell '/data/local/tmp/qjs --version'"
log "Expect: $QUICKJS_NG_TAG (without the leading v)"
