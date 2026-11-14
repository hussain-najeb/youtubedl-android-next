#!/usr/bin/env bash







set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

: "${MODULE:=natives}"          

echo_config_once
require_dir "$YTDLP_ANDROID_DIR" "set YTDLP_ANDROID_DIR to your youtubedl-android-next checkout"
require_dir "$YTDLP_ANDROID_DIR/$MODULE" "Gradle module '$MODULE' not found in the checkout"
require_file "$YTDLP_ANDROID_DIR/$MODULE/build.gradle.kts" "'$MODULE' must be a real Gradle module"
require_cmd zip
require_cmd unzip
require_cmd patchelf

FULL_VER="$(python_full_version)"
JNI_ROOT="$YTDLP_ANDROID_DIR/$MODULE/src/main/jniLibs"

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
  local abi="$1" dest="$JNI_ROOT/$abi" name
  mkdir -p "$dest"
  
  for name in \
    libavcodec.so libavdevice.so libavfilter.so libavformat.so libavutil.so \
    libswresample.so libswscale.so libc++_shared.so \
    libaria2.so libaria2c.so libaria2.zip.so libaria2c.zip.so libffmpeg.zip.so.bak; do
    remove_if_present "$dest/$name"
  done
}

install_python_quickjs() {
  local abi="$1" dest="$JNI_ROOT/$abi"
  log "Installing Python/QuickJS payloads for $abi -> $dest"

  require_file "$OUT_DIR/python/$abi/libpython-${FULL_VER}-${abi}.so" "Python launcher for $abi"
  require_file "$OUT_DIR/python/$abi/libpython-${FULL_VER}-${abi}.zip.so" "Python runtime ZIP for $abi"
  require_file "$OUT_DIR/quickjs/$abi/libqjs.so" "QuickJS library for $abi"
  require_file "$OUT_DIR/quickjs/$abi/libqjs-cli.so" "QuickJS CLI for $abi"

  cp "$OUT_DIR/python/$abi/libpython-${FULL_VER}-${abi}.so"      "$dest/libpython.so"
  cp "$OUT_DIR/python/$abi/libpython-${FULL_VER}-${abi}.zip.so"  "$dest/libpython.zip.so"
  cp "$OUT_DIR/quickjs/$abi/libqjs.so"               "$dest/libqjs.so"
  cp "$OUT_DIR/quickjs/$abi/libqjs-cli.so"           "$dest/libqjs-cli.so"
}

install_ffmpeg() {
  local abi="$1" dest="$JNI_ROOT/$abi"
  log "Installing FFmpeg payloads for $abi -> $dest"

  require_file "$OUT_DIR/ffmpeg/$abi/libffmpeg.so" "FFmpeg executable for $abi"
  require_file "$OUT_DIR/ffmpeg/$abi/libffprobe.so" "ffprobe executable for $abi"

  cp "$OUT_DIR/ffmpeg/$abi/libffmpeg.so"  "$dest/libffmpeg.so"
  cp "$OUT_DIR/ffmpeg/$abi/libffprobe.so" "$dest/libffprobe.so"

  
  local tmp libcxx
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/usr/lib"

  find "$OUT_DIR/ffmpeg/$abi" -maxdepth 1 -type f -name '*.so' \
    ! -name 'libffmpeg.so' ! -name 'libffprobe.so' \
    -exec cp {} "$tmp/usr/lib/" \;

  libcxx="$(ndk_libcxx_for_abi "$abi")"
  require_file "$libcxx" "NDK libc++_shared.so for $abi"
  cp "$libcxx" "$tmp/usr/lib/libc++_shared.so"

  rm -f "$dest/libffmpeg.zip.so"
  (cd "$tmp" && zip -q -r "$dest/libffmpeg.zip.so" usr)
  rm -rf "$tmp"

  require_file "$dest/libffmpeg.zip.so" "FFmpeg runtime ZIP for $abi"
}

install_aria2() {
  local abi="$1" dest="$JNI_ROOT/$abi"
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
  install_python_quickjs "$abi"
  install_ffmpeg "$abi"
  install_aria2 "$abi"
}

for_each_abi install_for_abi

log "Rebuilding :$MODULE AAR"
(cd "$YTDLP_ANDROID_DIR" && ./gradlew ":$MODULE:clean" && ./gradlew ":$MODULE:assembleRelease")

AAR="$(find "$YTDLP_ANDROID_DIR/$MODULE/build/outputs/aar" -maxdepth 1 -name '*release*.aar' 2>/dev/null | head -1)"
[ -n "$AAR" ] || die "no release AAR found under $YTDLP_ANDROID_DIR/$MODULE/build/outputs/aar"
require_file "$AAR" "expected AAR output"
unzip -t "$AAR" >/dev/null

log "AAR payload validation: $AAR"
for abi in $ABIS; do
  echo "===== $abi ====="

  for name in \
    libpython.so libpython.zip.so libqjs.so libqjs-cli.so \
    libffmpeg.so libffprobe.so libffmpeg.zip.so \
    libaria2c.so libaria2.zip.so; do
    unzip -Z1 "$AAR" | grep -x "jni/$abi/$name" >/dev/null \
      || die "missing jni/$abi/$name from $MODULE AAR"
  done

  
  if unzip -Z1 "$AAR" | grep -Eq "^jni/$abi/(libav(codec|device|filter|format|util)|libsw(resample|scale)|libc\+\+_shared)\.so$"; then
    die "loose FFmpeg/libc++ dependency leaked into $MODULE AAR for $abi"
  fi
done

log "AAR ready: $AAR"


if [ -n "${APP_DIR:-}" ]; then
  require_dir "$APP_DIR" "APP_DIR"
  mkdir -p "$APP_DIR/libs"
  log "Syncing rebuilt AAR into $APP_DIR/libs/${MODULE}-local.aar"
  cp "$AAR" "$APP_DIR/libs/${MODULE}-local.aar"
  warn "Make sure the app declares: implementation(files(\"libs/${MODULE}-local.aar\"))"
fi
