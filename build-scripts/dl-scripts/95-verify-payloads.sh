#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

: "${MODULE:=natives}"
: "${MODULE_X86_64:=natives-x86_64}"

require_cmd adb
adb get-state >/dev/null 2>&1 || die "no adb device/emulator attached"

DEVICE_ABI="$(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
log "Device primary ABI: $DEVICE_ABI"
case " $ABIS " in
  *" $DEVICE_ABI "*) ;;
  *) die "device ABI $DEVICE_ABI is not in ABIS=\"$ABIS\" — nothing built for it" ;;
esac

if [ "$DEVICE_ABI" = "x86_64" ]; then
  JNI_ROOT="$YTDLP_ANDROID_DIR/$MODULE_X86_64/src/main/jniLibs"
else
  JNI_ROOT="$YTDLP_ANDROID_DIR/$MODULE/src/main/jniLibs"
fi

TMP=/data/local/tmp

push() { adb push "$1" "$TMP/$2" >/dev/null && log "pushed $2"; }

log "--- QuickJS ---"
push "$OUT_DIR/quickjs/$DEVICE_ABI/libqjs-cli.so" qjs
adb shell chmod 755 "$TMP/qjs"
adb shell "LD_LIBRARY_PATH=$TMP $TMP/qjs --version"

log "--- FFmpeg / ffprobe ---"

for so in "$OUT_DIR/ffmpeg/$DEVICE_ABI"/*.so; do
  [ -f "$so" ] || continue
  case "$so" in *.zip.so|*.tar.xz.so) continue ;; esac
  push "$so" "$(basename "$so")"
done

FFMPEG_ARCHIVE="$JNI_ROOT/$DEVICE_ABI/libffmpeg.tar.xz.so"
require_file "$FFMPEG_ARCHIVE" "FFmpeg runtime archive for $DEVICE_ABI"
LIBCXX_TMP="$(mktemp)"
tar -xJf "$FFMPEG_ARCHIVE" -O usr/lib/libc++_shared.so > "$LIBCXX_TMP"
push "$LIBCXX_TMP" libc++_shared.so
rm -f "$LIBCXX_TMP"

adb shell chmod 755 "$TMP/libffmpeg.so" "$TMP/libffprobe.so"

adb shell "LD_LIBRARY_PATH=$TMP $TMP/libffmpeg.so -version" | head -1

adb shell "LD_LIBRARY_PATH=$TMP $TMP/libffmpeg.so -protocols" | grep -E 'https|tls' \
  || warn "no https/tls protocol support detected — FFmpeg ELF is fine, network is not (doc section 99)"

adb shell "LD_LIBRARY_PATH=$TMP $TMP/libffprobe.so -version" | head -1

log "--- aria2-next + bundled TLS ---"
PYTHON_ARCHIVE="$JNI_ROOT/$DEVICE_ABI/libpython.tar.xz.so"
require_file "$PYTHON_ARCHIVE" "Python runtime archive for $DEVICE_ABI"
PY_LIBS_STAGE="$(mktemp -d)"
tar -xJf "$PYTHON_ARCHIVE" --wildcards \
  'usr/lib/libcrypto.so*' 'usr/lib/libssl.so*' 'usr/lib/libsqlite3.so*' \
  'usr/lib/libexpat.so*' 'usr/lib/libz.so*' -C "$PY_LIBS_STAGE"
for so_name in libcrypto.so.3 libssl.so.3 libsqlite3.so libexpat.so.1 libz.so.1; do
  so_real="$(readlink -f "$PY_LIBS_STAGE/usr/lib/$so_name")"
  require_file "$so_real" "$so_name in libpython.tar.xz.so"
  push "$so_real" "$so_name"
done
rm -rf "$PY_LIBS_STAGE"

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
adb shell "LD_LIBRARY_PATH=$TMP $TMP/aria2/usr/bin/aria2c --version"
adb shell "LD_LIBRARY_PATH=$TMP $TMP/aria2/usr/bin/aria2c https://example.com/ -d $TMP/aria2-download -o example.html --check-certificate=true --console-log-level=warn --summary-interval=0"
adb shell test -s "$TMP/aria2-download/example.html" \
  || die "aria2-next HTTPS test did not produce a non-empty example.html"

log "--- ELF diagnostics (doc section 98) ---"
for b in libqjs-cli.so libffmpeg.so libffprobe.so; do
  echo "== $b =="
  readelf -l "$OUT_DIR"/*/"$DEVICE_ABI"/"$b" 2>/dev/null | grep -E 'INTERP|Requesting program interpreter' || true
done

log "--- Archive payload sanity (doc section 99: never ELF-strip archive .so files) ---"
FULL_VER="$(python_full_version)"
xz -t "$OUT_DIR/python/${DEVICE_ABI}/libpython-${FULL_VER}-${DEVICE_ABI}.tar.xz.so"
unzip -t "$OUT_DIR/aria2/${DEVICE_ABI}/libaria2-${DEVICE_ABI}.zip.so" | tail -3

cat <<'EOF'

--- Final integrated check (doc section 100) ---
Install the rebuilt AAR/APK on this device and run yt-dlp -v.  It's this exact shape of output:

  [debug] Request Handlers: urllib, curl_cffi
  [debug] JS runtimes: quickjs-ng-<version>
EOF
