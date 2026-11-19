#!/usr/bin/env bash







set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

: "${MODULE:=natives}"
: "${MODULE_X86_64:=natives-x86_64}"
: "${ONLY_PYTHON:=0}"
: "${ONLY_QUICKJS:=0}"
: "${ONLY_FFMPEG:=0}"
: "${ONLY_ARIA2:=0}"
: "${ONLY_LIBFFI:=0}"
: "${ONLY_CFFI:=0}"
: "${ONLY_CURL_IMPERSONATE:=0}"
: "${ONLY_CURL_CFFI:=0}"
: "${REQUIRE_ALL_PAYLOADS:=0}"
: "${STRICT_PARTIAL:=0}"
: "${ALL_ABIS:=arm64-v8a armeabi-v7a x86_64}"

if [ "$ONLY_LIBFFI" = "1" ] && [ "$ONLY_CFFI" != "1" ]; then
  warn "ONLY_LIBFFI set: implying ONLY_CFFI=1"
  ONLY_CFFI=1
fi
if [ "$ONLY_CURL_IMPERSONATE" = "1" ] && [ "$ONLY_CURL_CFFI" != "1" ]; then
  warn "ONLY_CURL_IMPERSONATE set: implying ONLY_CURL_CFFI=1"
  ONLY_CURL_CFFI=1
fi
if [ "$ONLY_LIBFFI" = "1" ] || [ "$ONLY_CFFI" = "1" ] || [ "$ONLY_CURL_IMPERSONATE" = "1" ] || [ "$ONLY_CURL_CFFI" = "1" ]; then
  if [ "$ONLY_PYTHON" != "1" ]; then
    warn "ONLY_LIBFFI / ONLY_CFFI / ONLY_CURL_IMPERSONATE / ONLY_CURL_CFFI set: implying ONLY_PYTHON=1 so rebuilt wheels are installed via libpython.zip.so"
    ONLY_PYTHON=1
  fi
fi

echo_config_once
require_dir "$YTDLP_ANDROID_DIR" "set YTDLP_ANDROID_DIR to your youtubedl-android-next checkout"
require_dir "$YTDLP_ANDROID_DIR/$MODULE" "Gradle module '$MODULE' not found in the checkout"
require_file "$YTDLP_ANDROID_DIR/$MODULE/build.gradle.kts" "'$MODULE' must be a real Gradle module"
require_dir "$YTDLP_ANDROID_DIR/$MODULE_X86_64" "Gradle module '$MODULE_X86_64' not found in the checkout"
require_file "$YTDLP_ANDROID_DIR/$MODULE_X86_64/build.gradle.kts" "'$MODULE_X86_64' must be a real Gradle module"
require_cmd zip
require_cmd unzip
require_cmd patchelf

SKIPPED_COMPONENTS=()

any_only_selected() {
  [ "$ONLY_PYTHON" = "1" ] || [ "$ONLY_QUICKJS" = "1" ] || [ "$ONLY_FFMPEG" = "1" ] || [ "$ONLY_ARIA2" = "1" ]
}

should_install_component() {
  local comp="$1" abi="$2" flag_val="$3" check_path="$4"
  if any_only_selected; then
    if [ "$flag_val" = "1" ]; then
      return 0
    fi
    SKIPPED_COMPONENTS+=("$abi:$comp (filtered out by ONLY_* flags)")
    return 1
  fi
  if [ "$REQUIRE_ALL_PAYLOADS" = "1" ] || [ -e "$check_path" ]; then
    return 0
  fi
  warn "Skipping $comp install for $abi ($check_path not built in OUT_DIR; keeping existing jniLibs payload)"
  SKIPPED_COMPONENTS+=("$abi:$comp (missing $check_path)")
  return 1
}

FULL_VER=""
if [ -f "$TERMUX_PACKAGES_DIR/packages/python/build.sh" ] || [ "$ONLY_PYTHON" = "1" ] || [ "$REQUIRE_ALL_PAYLOADS" = "1" ]; then
  FULL_VER="$(python_full_version)"
else
  FULL_VER="$(find "$OUT_DIR"/python -maxdepth 2 -type f -name 'libpython-*-*.so' 2>/dev/null | sed -n -E 's|.*/libpython-([0-9]+\.[0-9]+\.[0-9]+)-.*|\1|p' | head -n 1 || true)"
fi

module_for_abi() {
  case "$1" in
    x86_64) echo "$MODULE_X86_64" ;;
    *)      echo "$MODULE" ;;
  esac
}

jni_root_for_abi() {
  local mod
  mod="$(module_for_abi "$1")"
  echo "$YTDLP_ANDROID_DIR/$mod/src/main/jniLibs"
}

ndk_libcxx_for_abi() {
  local abi="$1" triple
  case "$abi" in
    arm64-v8a)   triple="aarch64-linux-android" ;;
    armeabi-v7a) triple="arm-linux-androideabi" ;;
    x86_64)      triple="x86_64-linux-android" ;;
    *) die "unsupported ABI for libc++ runtime: $abi" ;;
  esac
  echo "$TERMUX_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$triple/libc++_shared.so"
}

remove_if_present() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    log "Removing stale payload: $path"
    rm -f "$path"
  fi
}

clean_stale_for_abi() {
  local abi="$1" dest name
  dest="$(jni_root_for_abi "$abi")/$abi"
  mkdir -p "$dest"
  
  for name in \
    libavcodec.so libavdevice.so libavfilter.so libavformat.so libavutil.so \
    libswresample.so libswscale.so libc++_shared.so \
    libaria2.so libaria2c.zip.so libffmpeg.zip.so.bak; do
    remove_if_present "$dest/$name"
  done
}

install_python() {
  local abi="$1" dest
  dest="$(jni_root_for_abi "$abi")/$abi"
  log "Installing Python payloads for $abi -> $dest"

  [ -n "$FULL_VER" ] || FULL_VER="$(python_full_version)"
  require_file "$OUT_DIR/python/$abi/libpython-${FULL_VER}-${abi}.so" "Python launcher for $abi"
  require_file "$OUT_DIR/python/$abi/libpython-${FULL_VER}-${abi}.zip.so" "Python runtime ZIP for $abi"

  cp "$OUT_DIR/python/$abi/libpython-${FULL_VER}-${abi}.so"      "$dest/libpython.so"
  cp "$OUT_DIR/python/$abi/libpython-${FULL_VER}-${abi}.zip.so"  "$dest/libpython.zip.so"
}

install_quickjs() {
  local abi="$1" dest
  dest="$(jni_root_for_abi "$abi")/$abi"
  log "Installing QuickJS payloads for $abi -> $dest"

  require_file "$OUT_DIR/quickjs/$abi/libqjs.so" "QuickJS library for $abi"
  require_file "$OUT_DIR/quickjs/$abi/libqjs-cli.so" "QuickJS CLI for $abi"

  cp "$OUT_DIR/quickjs/$abi/libqjs.so"               "$dest/libqjs.so"
  cp "$OUT_DIR/quickjs/$abi/libqjs-cli.so"           "$dest/libqjs-cli.so"
}

install_ffmpeg() {
  local abi="$1" dest
  dest="$(jni_root_for_abi "$abi")/$abi"
  log "Installing FFmpeg payloads for $abi -> $dest"

  require_file "$OUT_DIR/ffmpeg/$abi/libffmpeg.so" "FFmpeg executable for $abi"
  require_file "$OUT_DIR/ffmpeg/$abi/libffprobe.so" "ffprobe executable for $abi"

  cp "$OUT_DIR/ffmpeg/$abi/libffmpeg.so"  "$dest/libffmpeg.so"
  cp "$OUT_DIR/ffmpeg/$abi/libffprobe.so" "$dest/libffprobe.so"

  
  local tmp libcxx
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/usr/lib"

  find "$OUT_DIR/ffmpeg/$abi" -maxdepth 1 -type f -name '*.so' \
    ! -name 'libffmpeg.so' ! -name 'libffprobe.so' ! -name '*.zip.so' \
    -exec cp {} "$tmp/usr/lib/" \;

  libcxx="$(ndk_libcxx_for_abi "$abi")"
  require_file "$libcxx" "NDK libc++_shared.so for $abi"
  cp "$libcxx" "$tmp/usr/lib/libc++_shared.so"
  local strip_bin="$TERMUX_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
  if [ -x "$strip_bin" ]; then
    "$strip_bin" --strip-unneeded "$tmp/usr/lib/libc++_shared.so"
  fi

  rm -f "$dest/libffmpeg.zip.so"
  (cd "$tmp" && zip -q -r "$dest/libffmpeg.zip.so" usr)
  rm -rf "$tmp"

  require_file "$dest/libffmpeg.zip.so" "FFmpeg runtime ZIP for $abi"
}

install_aria2() {
  local abi="$1" dest
  dest="$(jni_root_for_abi "$abi")/$abi"
  local bundle="$OUT_DIR/aria2/${abi}/libaria2-${abi}.zip.so"
  log "Installing aria2c payloads for $abi -> $dest"

  require_file "$bundle" "aria2 runtime bundle for $abi"

  
  cp "$bundle" "$dest/libaria2.zip.so"

  
  
  unzip -p "$bundle" usr/bin/aria2c.real > "$dest/libaria2c.so"
  chmod 0755 "$dest/libaria2c.so"
  patchelf --remove-rpath "$dest/libaria2c.so"

  require_file "$dest/libaria2c.so" "aria2c native executable for $abi"
}

install_for_abi() {
  local abi="$1"
  clean_stale_for_abi "$abi"
  if should_install_component "python" "$abi" "$ONLY_PYTHON" "$OUT_DIR/python/$abi/libpython-${FULL_VER:-none}-${abi}.so"; then
    install_python "$abi"
  fi
  if should_install_component "quickjs" "$abi" "$ONLY_QUICKJS" "$OUT_DIR/quickjs/$abi/libqjs.so"; then
    install_quickjs "$abi"
  fi
  if should_install_component "ffmpeg" "$abi" "$ONLY_FFMPEG" "$OUT_DIR/ffmpeg/$abi/libffmpeg.so"; then
    install_ffmpeg "$abi"
  fi
  if should_install_component "aria2" "$abi" "$ONLY_ARIA2" "$OUT_DIR/aria2/${abi}/libaria2-${abi}.zip.so"; then
    install_aria2 "$abi"
  fi
}

for_each_abi install_for_abi

print_partial_summary() {
  if (( ${#SKIPPED_COMPONENTS[@]} > 0 )); then
    warn "============================================================"
    warn "PARTIAL INSTALL SUMMARY: ${#SKIPPED_COMPONENTS[@]} component(s) were NOT updated from OUT_DIR:"
    for item in "${SKIPPED_COMPONENTS[@]}"; do
      warn "  - $item"
    done
    warn "Existing jniLibs payloads for these components will be packaged as-is."
    warn "============================================================"
  fi
}

print_partial_summary

if (( ${#SKIPPED_COMPONENTS[@]} > 0 )) && ! any_only_selected && [ "$STRICT_PARTIAL" = "1" ]; then
  die "STRICT_PARTIAL=1: refusing to proceed with missing OUT_DIR components (${#SKIPPED_COMPONENTS[@]} skipped) without explicit ONLY_* flags"
fi

for abi in $ALL_ABIS; do
  dest="$(jni_root_for_abi "$abi")/$abi"
  for name in \
    libpython.so libpython.zip.so libqjs.so libqjs-cli.so \
    libffmpeg.so libffprobe.so libffmpeg.zip.so \
    libaria2c.so libaria2.zip.so; do
    require_file "$dest/$name" "pre-Gradle jniLibs check for $abi ($name)"
  done
done

log "Rebuilding :$MODULE and :$MODULE_X86_64 AARs"
(cd "$YTDLP_ANDROID_DIR" && ./gradlew ":$MODULE:clean" ":$MODULE_X86_64:clean" && ./gradlew ":$MODULE:assembleRelease" ":$MODULE_X86_64:assembleRelease")

for abi in $ALL_ABIS; do
  mod="$(module_for_abi "$abi")"
  AAR="$(find "$YTDLP_ANDROID_DIR/$mod/build/outputs/aar" -maxdepth 1 -name '*release*.aar' 2>/dev/null | head -1)"
  [ -n "$AAR" ] || die "no release AAR found under $YTDLP_ANDROID_DIR/$mod/build/outputs/aar"
  require_file "$AAR" "expected AAR output"
  unzip -t "$AAR" >/dev/null

  echo "===== $abi ($mod: $AAR) ====="

  for name in \
    libpython.so libpython.zip.so libqjs.so libqjs-cli.so \
    libffmpeg.so libffprobe.so libffmpeg.zip.so \
    libaria2c.so libaria2.zip.so; do
    unzip -Z1 "$AAR" | grep -x "jni/$abi/$name" >/dev/null \
      || die "missing jni/$abi/$name from $mod AAR"
  done

  if unzip -Z1 "$AAR" | grep -Eq "^jni/$abi/(libav(codec|device|filter|format|util)|libsw(resample|scale)|libc\+\+_shared)\.so$"; then
    die "loose FFmpeg/libc++ dependency leaked into $mod AAR for $abi"
  fi
done

AAR="$(find "$YTDLP_ANDROID_DIR/$MODULE/build/outputs/aar" -maxdepth 1 -name '*release*.aar' 2>/dev/null | head -1)"
log "AAR ready: $AAR"

print_partial_summary


if [ -n "${APP_DIR:-}" ]; then
  require_dir "$APP_DIR" "APP_DIR"
  mkdir -p "$APP_DIR/libs"
  log "Syncing rebuilt AAR into $APP_DIR/libs/${MODULE}-local.aar"
  cp "$AAR" "$APP_DIR/libs/${MODULE}-local.aar"
  warn "Make sure the app declares: implementation(files(\"libs/${MODULE}-local.aar\"))"
fi
