#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

: "${MODULE:=main-lib}"
JNI_ROOT="$YTDLP_ANDROID_DIR/$MODULE/src/main/jniLibs"

require_cmd adb
adb get-state >/dev/null 2>&1 || die "no adb device/emulator attached"

DEVICE_ABI="$(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
log "Device primary ABI: $DEVICE_ABI"
case " $ABIS " in
  *" $DEVICE_ABI "*) ;;
  *) die "device ABI $DEVICE_ABI is not in ABIS=\"$ABIS\" — nothing built for it" ;;
esac

TMP=/data/local/tmp

push() { adb push "$1" "$TMP/$2" >/dev/null && log "pushed $2"; }

log "--- QuickJS ---"
push "$OUT_DIR/quickjs/$DEVICE_ABI/libqjs-cli.so" qjs
push "$OUT_DIR/quickjs/$DEVICE_ABI/libqjs.so" libqjs.so
adb shell chmod 755 "$TMP/qjs"
adb shell "LD_LIBRARY_PATH=$TMP $TMP/qjs --version"

log "--- FFmpeg / ffprobe ---"

for so in "$OUT_DIR/ffmpeg/$DEVICE_ABI"/*.so; do
  [ -f "$so" ] || continue
  push "$so" "$(basename "$so")"
done

FFMPEG_ZIP="$JNI_ROOT/$DEVICE_ABI/libffmpeg.zip.so"
require_file "$FFMPEG_ZIP" "FFmpeg runtime ZIP for $DEVICE_ABI"
LIBCXX_TMP="$(mktemp)"
unzip -p "$FFMPEG_ZIP" usr/lib/libc++_shared.so > "$LIBCXX_TMP"
push "$LIBCXX_TMP" libc++_shared.so
rm -f "$LIBCXX_TMP"

adb shell chmod 755 "$TMP/libffmpeg.so" "$TMP/libffprobe.so"

adb shell "LD_LIBRARY_PATH=$TMP $TMP/libffmpeg.so -version" | head -1

adb shell "LD_LIBRARY_PATH=$TMP $TMP/libffmpeg.so -protocols" | grep -E 'https|tls' \
  || warn "no https/tls protocol support detected — FFmpeg ELF is fine, network is not (doc section 99)"

adb shell "LD_LIBRARY_PATH=$TMP $TMP/libffprobe.so -version" | head -1

log "--- aria2-next + bundled TLS ---"
ARIA2_BUNDLE="$OUT_DIR/aria2/$DEVICE_ABI/libaria2-$DEVICE_ABI.zip.so"
require_file "$ARIA2_BUNDLE" "aria2 runtime bundle for $DEVICE_ABI"
ARIA2_STAGE="$(mktemp -d)"
trap 'rm -rf "$ARIA2_STAGE"' EXIT
unzip -q "$ARIA2_BUNDLE" -d "$ARIA2_STAGE"
require_file "$ARIA2_STAGE/usr/bin/aria2c" "aria2 wrapper in bundle"
require_file "$ARIA2_STAGE/usr/bin/aria2c.real" "aria2 executable in bundle"
require_file "$ARIA2_STAGE/usr/etc/tls/cert.pem" "bundled TLS certificate file"
adb shell "rm -rf $TMP/aria2 $TMP/aria2-download && mkdir -p $TMP/aria2 $TMP/aria2-download"
adb push "$ARIA2_STAGE/usr" "$TMP/aria2/" >/dev/null
adb shell chmod 755 "$TMP/aria2/usr/bin/aria2c" "$TMP/aria2/usr/bin/aria2c.real"
adb shell "$TMP/aria2/usr/bin/aria2c --version"
adb shell "$TMP/aria2/usr/bin/aria2c https://example.com/ -d $TMP/aria2-download -o example.html --check-certificate=true --console-log-level=warn --summary-interval=0"
adb shell test -s "$TMP/aria2-download/example.html" \
  || die "aria2-next HTTPS test did not produce a non-empty example.html"

log "--- ELF diagnostics (doc section 98) ---"
for b in libqjs-cli.so libffmpeg.so libffprobe.so; do
  echo "== $b =="
  readelf -l "$OUT_DIR"/*/"$DEVICE_ABI"/"$b" 2>/dev/null | grep -E 'INTERP|Requesting program interpreter' || true
done

log "--- ZIP payload sanity (doc section 99: never ELF-strip .zip.so files) ---"
FULL_VER="$(python_full_version)"
unzip -t "$OUT_DIR/python/${DEVICE_ABI}/libpython-${FULL_VER}-${DEVICE_ABI}.zip.so" | tail -3
unzip -t "$OUT_DIR/aria2/${DEVICE_ABI}/libaria2-${DEVICE_ABI}.zip.so" | tail -3

cat <<'EOF'

--- Final integrated check (doc section 100) ---
Install the rebuilt AAR/APK on this device and run yt-dlp -v.  It's this exact shape of output:

  [debug] Request Handlers: urllib, curl_cffi
  [debug] JS runtimes: quickjs-ng-<version>
EOF
