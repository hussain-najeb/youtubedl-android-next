#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

: "${WORK_ROOT:=$BASE_DIR/build}"
: "${TERMUX_PACKAGES_DIR:=$BASE_DIR/termux-packages}"
: "${YTDLP_ANDROID_DIR:=$BASE_DIR/youtubedl-android-next}"
: "${QUICKJS_DIR:=$WORK_ROOT/quickjs-ng-src}"
: "${FFMPEG_MAKER_DIR:=$WORK_ROOT/ffmpeg-android-maker}"
: "${CURL_IMPERSONATE_DIR:=$WORK_ROOT/curl-impersonate-src}"
: "${CURL_CFFI_SRC_DIR:=$WORK_ROOT/curl_cffi-src}"
: "${CFFI_SRC_DIR:=$WORK_ROOT/cffi-src}"
: "${OUT_DIR:=$BASE_DIR/out}"          
: "${WHEELHOUSE_DIR:=$WORK_ROOT/wheelhouse}"

: "${FERMUX_APP_DIR:=}"

: "${ANDROID_SDK_ROOT:=$HOME/Android/Sdk}"

: "${TERMUX_NDK_ROOT:=$BASE_DIR/android-ndk-r30}"
: "${TERMUX_NDK_CONTAINER_ROOT:=/opt/fermux/android-ndk-r30}"

: "${TERMUX_JAVA_HOME:=}"
if [ -z "$TERMUX_JAVA_HOME" ]; then
  _fermux_java_bin="$(command -v java 2>/dev/null || true)"
  [ -n "$_fermux_java_bin" ] || { echo "[FAIL] required command not found: java" >&2; read -p "Press Enter to exit..." dummy; exit 1; }
  _fermux_java_bin="$(readlink -f "$_fermux_java_bin")"
  TERMUX_JAVA_HOME="$(dirname "$(dirname "$_fermux_java_bin")")"
fi
[ -x "$TERMUX_JAVA_HOME/bin/java" ] || {
  echo "[FAIL] TERMUX_JAVA_HOME does not contain an executable bin/java: $TERMUX_JAVA_HOME" >&2
  read -p "Press Enter to exit..." dummy
  exit 1
}
export TERMUX_JAVA_HOME
export JAVA_HOME="$TERMUX_JAVA_HOME"
unset _fermux_java_bin

: "${API_LEVEL:=24}"

export CIBW_BUILD="${CIBW_BUILD:-cp314-*}"

: "${ABIS:=arm64-v8a armeabi-v7a x86 x86_64}"

: "${TERMUX_PACKAGES_COMMIT:=d08cf6a8e256be9c9fc019430f6af5833d726980}"
: "${CURL_IMPERSONATE_COMMIT:=5b1c3542fc7fc0e9fe623a6c9a848d16f92fe99a}"
: "${FFMPEG_MAKER_COMMIT:=dd72b161ae5c759fd25a5cab971a3ff710f0bdba}"
: "${QUICKJS_NG_COMMIT:=e22ce4de4362dc5fd4794cfa3c03fc7fdba5f015}"
: "${CURL_CFFI_COMMIT:=78301ad1ce8bb042a451ffdb05d3037ac9fa2ed1}"

: "${CFFI_VERSION:=2.1.1}"
: "${CFFI_SHA256:=dd31f52ea1086513bb9df30f8fcee9b8918323ae067a3d5b78bc826a000712be}"
: "${LIBFFI_TAG:=v3.8.0}"
: "${CURL_CFFI_VERSION:=0.17.0b2}"
# 0 = build arm64-v8a curl_cffi from CURL_CFFI_COMMIT like the other ABIs (default)
# 1 = download the official PyPI wheel for arm64-v8a instead
: "${ARM64_USE_OFFICIAL_CURL_CFFI:=0}"

: "${QUICKJS_NG_TAG:=v0.18.0}"
: "${MUTAGEN_VERSION:=1.48.1}"
: "${CERTIFI_VERSION:=2026.10.23}"
: "${CIBUILDWHEEL_VERSION:=4.3.5}"
: "${TERMUX_HOST_LLVM_MAJOR_VERSION:=21}"
: "${TERMUX_NDK_REVISION:=30.0.16248370}"
: "${ARIA2_NEXT_VERSION:=3.0.10}"
: "${ARIA2_NEXT_COMMIT:=6148910b42fd472e5155fb4539a18740df24e97d}"

: "${TERMUX_BUILDER_IMAGE:=ghcr.io/termux/package-builder}"
: "${TERMUX_BUILDER_IMAGE_DIGEST:=sha256:44999857244619e25bc8e3427904a16d36cc0c0e087704af039e5bdf94814ac9}"
: "${TERMUX_BUILDER_IMAGE_NAME:=$TERMUX_BUILDER_IMAGE@$TERMUX_BUILDER_IMAGE_DIGEST}"
: "${CONTAINER_NAME:=termux-package-builder-${TERMUX_PACKAGES_COMMIT:0:12}}"

: "${TERMUX_DOCKER_RUN_EXTRA_ARGS:=}"
TERMUX_DOCKER_RUN_EXTRA_ARGS="--volume ${TERMUX_NDK_ROOT}:${TERMUX_NDK_CONTAINER_ROOT}:ro,z ${TERMUX_DOCKER_RUN_EXTRA_ARGS}"

: "${TERMUX_DOCKER_EXEC_EXTRA_ARGS:=}"
TERMUX_DOCKER_EXEC_EXTRA_ARGS="--env NDK=${TERMUX_NDK_CONTAINER_ROOT} --env TERMUX_HOST_LLVM_MAJOR_VERSION=${TERMUX_HOST_LLVM_MAJOR_VERSION} ${TERMUX_DOCKER_EXEC_EXTRA_ARGS}"

export TERMUX_DOCKER_RUN_EXTRA_ARGS
export TERMUX_DOCKER_EXEC_EXTRA_ARGS

mkdir -p "$WORK_ROOT" "$OUT_DIR" "$WHEELHOUSE_DIR"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; read -p "Press Enter to exit..." dummy; exit 1; }

reconstructed() { printf '\033[1;35m[RECONSTRUCTED]\033[0m %s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_dir() {
  [ -d "$1" ] || die "expected directory does not exist: $1 ($2)"
}

require_file() {
  [ -f "$1" ] || die "expected file does not exist: $1 ($2)"
}

abi_termux_arch() {
  case "$1" in
    arm64-v8a)   echo "aarch64" ;;
    armeabi-v7a) echo "arm" ;;
    x86)         echo "i686" ;;
    x86_64)      echo "x86_64" ;;
    *) die "unknown ABI: $1" ;;
  esac
}

abi_cibw_arch() {
  case "$1" in
    arm64-v8a) echo "arm64_v8a" ;;
    x86_64)    echo "x86_64" ;;
    armeabi-v7a|x86) echo "" ;;
    *) die "unknown ABI: $1" ;;
  esac
}

abi_ndk_triple() {
  case "$1" in
    arm64-v8a)   echo "aarch64-linux-android" ;;
    armeabi-v7a) echo "armv7a-linux-androideabi" ;;
    x86)         echo "i686-linux-android" ;;
    x86_64)      echo "x86_64-linux-android" ;;
    *) die "unknown ABI: $1" ;;
  esac
}

abi_cmake_abi() { echo "$1"; }

for_each_abi() {
  local fn="$1"
  local abi
  for abi in $ABIS; do
    log "=== ABI: $abi ==="
    "$fn" "$abi"
  done
}

termux_runtime_root() {
  local abi="$1"
  echo "$WORK_ROOT/termux-runtime-$abi"
}

termux_runtime_prefix() {
  local abi="$1"
  echo "$(termux_runtime_root "$abi")/data/data/com.termux/files/usr"
}

termux_builder_cache_dir() {
  echo "$TERMUX_PACKAGES_DIR/.fermux-build-cache"
}

python_stage_dir() {
  local abi="$1"
  echo "$WORK_ROOT/python-bundle-$abi"
}

site_packages_dir() {
  local abi="$1"
  local py_majmin
  py_majmin="$(python_major_minor)"
  echo "$(python_stage_dir "$abi")/usr/lib/python${py_majmin}/site-packages"
}

python_full_version() {
  local build_sh="$TERMUX_PACKAGES_DIR/packages/python/build.sh"
  local version
  require_file "$build_sh" "termux-packages checkout"
  version="$(sed -n -E \
    -e 's/^TERMUX_PKG_VERSION=["\x27]?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' \
    -e 's/^[[:space:]]*["\x27]([0-9]+\.[0-9]+\.[0-9]+)["\x27].*/\1/p' \
    "$build_sh" | head -n 1)"
  [ -n "$version" ] || die "unable to parse CPython version from $build_sh"
  printf '%s\n' "$version"
}

python_major_minor() {
  python_full_version | cut -d. -f1,2
}

termux_build_package() {
  local termux_arch="$1"; shift
  local pkg="$1"; shift
  require_dir "$TERMUX_PACKAGES_DIR" "set TERMUX_PACKAGES_DIR to your termux-packages checkout"
  (
    cd "$TERMUX_PACKAGES_DIR"
    export TERMUX_JAVA_HOME TERMUX_BUILDER_IMAGE_NAME CONTAINER_NAME TERMUX_DOCKER_RUN_EXTRA_ARGS
    export JAVA_HOME="$TERMUX_JAVA_HOME"
    ./scripts/run-docker.sh ./build-package.sh -a "$termux_arch" "$@" "$pkg"
  )
}

echo_config_once() {
  log "BASE_DIR=$BASE_DIR"
  log "WORK_ROOT=$WORK_ROOT"
  log "ABIS=$ABIS"
  log "API_LEVEL=$API_LEVEL"
  log "TERMUX_PACKAGES_DIR=$TERMUX_PACKAGES_DIR"
  log "TERMUX_BUILDER_IMAGE_NAME=$TERMUX_BUILDER_IMAGE_NAME"
  log "CONTAINER_NAME=$CONTAINER_NAME"
  log "TERMUX_NDK_CONTAINER_ROOT=$TERMUX_NDK_CONTAINER_ROOT"
}

relocate_termux_elf_runpaths() {
    local stage="$1"
    local libdir="$stage/usr/lib"
    local f filedir rel old new count=0

    require_dir "$libdir"
    command -v patchelf >/dev/null 2>&1 || die "patchelf is required for ELF RUNPATH relocation"

    while IFS= read -r -d '' f; do
        file "$f" 2>/dev/null | grep -q 'ELF' || continue

        old="$(patchelf --print-rpath "$f" 2>/dev/null || true)"

        case "$old" in
            *"/data/data/com.termux/files/usr/lib"*) ;;
            *) continue ;;
        esac

        filedir="$(dirname "$f")"
        rel="$(realpath --relative-to="$filedir" "$libdir")"

        if [ "$rel" = "." ]; then
            new='$ORIGIN'
        else
            new="\$ORIGIN/$rel"
        fi

        log "Relocating RUNPATH: ${f#$stage/}: $old -> $new"
        patchelf --set-rpath "$new" "$f"
        count=$((count + 1))
    done < <(find "$libdir" -type f -print0)

    log "Relocated Termux RUNPATHs in $count ELF file(s)"
}

verify_no_termux_elf_runpaths() {
    local stage="$1"
    local libdir="$stage/usr/lib"
    local f rp bad=0

    require_dir "$libdir"

    while IFS= read -r -d '' f; do
        file "$f" 2>/dev/null | grep -q 'ELF' || continue

        rp="$(patchelf --print-rpath "$f" 2>/dev/null || true)"

        case "$rp" in
            *"/data/data/com.termux/"*)
                echo "[BAD RUNPATH] ${f#$stage/}: $rp" >&2
                bad=1
                ;;
        esac
    done < <(find "$libdir" -type f -print0)

    [ "$bad" -eq 0 ] || die "stale Termux RUNPATH found in staged runtime"
}
