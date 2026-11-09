#!/usr/bin/env bash














set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once

fetch_curl_impersonate_source() {
  if [ ! -d "$CURL_IMPERSONATE_DIR/.git" ]; then
    rm -rf "$CURL_IMPERSONATE_DIR"
    git clone --no-checkout --depth 1 https://github.com/lexiforest/curl-impersonate.git "$CURL_IMPERSONATE_DIR"
  fi
  git -C "$CURL_IMPERSONATE_DIR" fetch --depth 1 origin "$CURL_IMPERSONATE_COMMIT"
  git -C "$CURL_IMPERSONATE_DIR" checkout --force --detach "$CURL_IMPERSONATE_COMMIT"
  git -C "$CURL_IMPERSONATE_DIR" reset --hard "$CURL_IMPERSONATE_COMMIT"
  [ "$(git -C "$CURL_IMPERSONATE_DIR" rev-parse HEAD)" = "$CURL_IMPERSONATE_COMMIT" ] \
    || die "curl-impersonate checkout does not match pinned commit $CURL_IMPERSONATE_COMMIT"
  grep -Fq -- '-DENABLE_ARES=OFF' "$CURL_IMPERSONATE_DIR/CMakeLists.txt" \
    || die "pinned curl-impersonate source lacks upstream Android resolver configuration"
  grep -Fq -- '-DENABLE_THREADED_RESOLVER=ON' "$CURL_IMPERSONATE_DIR/CMakeLists.txt" \
    || die "pinned curl-impersonate source lacks upstream Android threaded resolver configuration"
  grep -Fq -- 'armv7-linux-android' "$CURL_IMPERSONATE_DIR/.github/workflows/build.yml" \
    || die "pinned curl-impersonate source lacks the upstream Android armv7 build target"
  grep -Fq -- 'x86-linux-android' "$CURL_IMPERSONATE_DIR/.github/workflows/build.yml" \
    || die "pinned curl-impersonate source lacks the upstream Android x86 build target"
}



needs_custom_curl_cffi() {
  case "$1" in
    arm64-v8a) [ "$ARM64_USE_OFFICIAL_CURL_CFFI" = "1" ] && return 1 || return 0 ;;
    *) return 0 ;;
  esac
}

build_curl_impersonate_for_abi() {
  local abi="$1"
  needs_custom_curl_cffi "$abi" || { log "Skipping curl-impersonate for $abi (official wheel exists)"; return; }

  local cmake_abi; cmake_abi="$(abi_cmake_abi "$abi")"
  local build_dir="$WORK_ROOT/curl-impersonate-build-$abi"
  local install_dir="$WORK_ROOT/curl-impersonate-install-$abi"
  rm -rf "$build_dir" "$install_dir"

  log "Configuring curl-impersonate for $abi (ANDROID_ABI=$cmake_abi)"
  cmake \
    -S "$CURL_IMPERSONATE_DIR" \
    -B "$build_dir" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TERMUX_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$cmake_abi" \
    -DANDROID_PLATFORM="android-$API_LEVEL" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DUSE_LIBIDN2=OFF \
    -DCURL_IMPERSONATE_CXX_RUNTIME_LIBRARY=c++

  cmake --build "$build_dir" --parallel "$(nproc)" \
    || { warn "high parallelism failed, retrying with --parallel 4"; cmake --build "$build_dir" --parallel 4; }

  
  
  local curl_cache="$build_dir/deps/build/curl/CMakeCache.txt"
  require_file "$curl_cache" "curl CMake cache for resolver verification"

  grep -qx 'ENABLE_ARES:BOOL=OFF' "$curl_cache" \
    || die "curl resolver misconfigured for $abi: ENABLE_ARES is not OFF"

  grep -qx 'ENABLE_THREADED_RESOLVER:BOOL=ON' "$curl_cache" \
    || die "curl resolver misconfigured for $abi: ENABLE_THREADED_RESOLVER is not ON"

  log "curl resolver verified: Android threaded resolver"

  cmake --install "$build_dir"

  local archive
  archive="$(find "$install_dir" "$build_dir" -type f -name 'libcurl-impersonate*.a' | head -1)"
  require_file "$archive" "libcurl-impersonate.a for $abi"
  log "curl-impersonate static lib ready for $abi: $archive"

  # Publish into the shared out/ tree (work dirs above stay in place for stage 40).
  local out="$OUT_DIR/curl-impersonate/$abi"
  rm -rf "$out"
  mkdir -p "$out/deps"
  cp "$archive" "$out/libcurl-impersonate.a"
  if [ -d "$install_dir/include" ]; then
    cp -a "$install_dir/include" "$out/"
  fi
  local deps_lib
  if [ -d "$build_dir/deps/install/lib" ]; then
    deps_lib="$build_dir/deps/install/lib"
  else
    deps_lib="$install_dir/lib"
  fi
  find "$deps_lib" -maxdepth 1 -type f -name '*.a' -exec cp -a {} "$out/deps/" \;
  log "curl-impersonate published for $abi -> $out"
}

fetch_curl_impersonate_source
for_each_abi build_curl_impersonate_for_abi
log "curl-impersonate build complete."
