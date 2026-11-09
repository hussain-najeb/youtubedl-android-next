#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once

if [ ! -d "$FFMPEG_MAKER_DIR/.git" ]; then
  log "Cloning ffmpeg-android-maker at pinned commit $FFMPEG_MAKER_COMMIT into $FFMPEG_MAKER_DIR"
  rm -rf "$FFMPEG_MAKER_DIR"
  git clone --no-checkout --depth 1 https://github.com/Javernaut/ffmpeg-android-maker.git "$FFMPEG_MAKER_DIR"
fi
git -C "$FFMPEG_MAKER_DIR" fetch --depth 1 origin "$FFMPEG_MAKER_COMMIT"
git -C "$FFMPEG_MAKER_DIR" checkout --force --detach "$FFMPEG_MAKER_COMMIT"
git -C "$FFMPEG_MAKER_DIR" reset --hard "$FFMPEG_MAKER_COMMIT"
[ "$(git -C "$FFMPEG_MAKER_DIR" rev-parse HEAD)" = "$FFMPEG_MAKER_COMMIT" ] \
  || die "ffmpeg-android-maker checkout does not match pinned commit $FFMPEG_MAKER_COMMIT"

# ffmpeg-android-maker is a plain build script with no hooks for our needs, so after the
# pinned checkout (which resets it to a clean copy every run) we patch its scripts in place.
# Three patches follow: the mbedTLS build step, FFmpeg's configure call, and the TLS detection.
ffmpeg_build_sh="$FFMPEG_MAKER_DIR/scripts/ffmpeg/build.sh"
require_file "$ffmpeg_build_sh" "ffmpeg-android-maker FFmpeg build script"

mbedtls_download_sh="$FFMPEG_MAKER_DIR/scripts/mbedtls/download.sh"
mbedtls_build_sh="$FFMPEG_MAKER_DIR/scripts/mbedtls/build.sh"
# Bump FreeType version to fix 404 download errors

sed -i "s/2.14.3/2.15.0/g" "$FFMPEG_MAKER_DIR/scripts/libfreetype/download.sh"

sed -i "s/2.14.3/2.15.0/g" "$FFMPEG_MAKER_DIR/scripts/libfreetype/build.sh"
require_file "$mbedtls_download_sh" "ffmpeg-android-maker mbedTLS download script"
require_file "$mbedtls_build_sh" "ffmpeg-android-maker mbedTLS build script"

# Patch 1: replace the maker's mbedTLS build step entirely.
#  - FFmpeg 9.x links mbedTLS manually (not via the old mechanism used in 8.x), so https/version3
#    are enabled here through EXTRA_BUILD_CONFIGURATION_FLAGS.
#  - -Werror is stripped and -Wno-error=unterminated-string-initialization is set, because that
#    warning inside mbedTLS's own sources otherwise fails the build.
#  - ENABLE_TESTING=0 / ENABLE_PROGRAMS=0 skip mbedTLS's test and example programs, which are not
#    needed and are one more thing that can fail to compile.
cat << 'MBED_EOF' > "$mbedtls_build_sh"
#!/usr/bin/env bash
CMAKE_BUILD_DIR=mbedtls_build_${ANDROID_ABI}
cd mbedtls-${MBEDTLS_VERSION}

sed -i 's/-Werror//g' CMakeLists.txt

rm -rf ${CMAKE_BUILD_DIR}
mkdir ${CMAKE_BUILD_DIR}
cd ${CMAKE_BUILD_DIR}
${CMAKE_EXECUTABLE} .. \
 -DANDROID_PLATFORM=${ANDROID_PLATFORM} \
 -DANDROID_ABI=${ANDROID_ABI} \
 -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_DIR}/mbedtls/android.cmake \
 -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
 -DENABLE_TESTING=0 \
 -DENABLE_PROGRAMS=0 \
 -DCMAKE_C_FLAGS="-Wno-error=unterminated-string-initialization"
${MAKE_EXECUTABLE} -j${HOST_NPROC}
${MAKE_EXECUTABLE} install
export EXTRA_BUILD_CONFIGURATION_FLAGS="${EXTRA_BUILD_CONFIGURATION_FLAGS} --enable-protocol=https --enable-version3"
MBED_EOF
chmod +x "$mbedtls_build_sh"

python3 - "$ffmpeg_build_sh" <<'PY_PATCH_FFMPEG'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text()

# Patch 2a: pass $CFLAGS through to FFmpeg's --extra-cflags so the file-prefix-map flags exported
# below actually reach FFmpeg (strips the build machine's home path from the binaries).

if '${CFLAGS:-}' not in s:
    s, n = re.subn(
        r'(--extra-cflags="[^"]*)(")',
        r'\1 ${CFLAGS:-}\2',
        s,
        count=1,
    )
    if n != 1:
        raise SystemExit("Could not patch FFmpeg --extra-cflags")

# Patch 2b: same for C++ flags ($CXXFLAGS -> --extra-cxxflags).
if '--extra-cxxflags=' not in s:
    lines = s.splitlines(keepends=True)

    for i, line in enumerate(lines):
        if '--extra-cflags=' in line:
            indent = line[:len(line) - len(line.lstrip())]
            lines.insert(
                i + 1,
                indent + '--extra-cxxflags="${CXXFLAGS:-}" \\\n'
            )
            break
    else:
        raise SystemExit("Could not locate FFmpeg --extra-cflags line")

    s = ''.join(lines)

# Disabled (if False): would add an $ORIGIN rpath at link time. The rpath is set with patchelf
# after the build instead (see verify_ffmpeg_for_abi).
if False and '--extra-ldexeflags=' not in s:
    lines = s.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if '--extra-cxxflags=' in line or '--extra-cflags=' in line:
            indent = line[:len(line) - len(line.lstrip())]

            j = i + 1
            while j < len(lines) and ('--extra-cxxflags=' in lines[j] or '--extra-cflags=' in lines[j]):
                j += 1
            lines.insert(j, indent + '--extra-ldexeflags="-Wl,-rpath,\\$ORIGIN" \\\n')
            break
    else:
        raise SystemExit("Could not locate FFmpeg linker flag insertion point")
    s = ''.join(lines)

# Patch 2c: after configure, overwrite FFMPEG_CONFIGURATION in config.h with a fixed string so the
# binary does not embed the full configure command line (and build paths). Runs once (marker check).
if 'Fermux: sanitize FFmpeg build metadata' not in s:
    needle = '$ADDITIONAL_COMPONENTS || exit 1\n'

    if needle not in s:
        raise SystemExit(
            "Could not locate end of FFmpeg configure command"
        )

    sanitizer = (
        '\n'
        '# Fermux: sanitize FFmpeg build metadata\n'
        'if [ -f config.h ]; then\n'
        '  sed -i \'s|^#define FFMPEG_CONFIGURATION .*|'
        '#define FFMPEG_CONFIGURATION "Android build"|\' config.h\n'
        'fi\n'
    )

    s = s.replace(needle, needle + sanitizer, 1)

# Patch 3: make FFmpeg's configure find mbedTLS without pkg-config by replacing
# require_pkg_config with a direct require that links -lmbedtls -lmbedx509 -lmbedcrypto.
# NOTE: this one fails silently - if configure's text changes, the sed just does nothing.
if 'require_pkg_config mbedtls' not in s:
    s = s.replace('./configure \\', "sed -i 's|require_pkg_config mbedtls mbedtls mbedtls/ssl.h mbedtls_ssl_init|require mbedtls mbedtls/ssl.h mbedtls_ssl_init -lmbedtls -lmbedx509 -lmbedcrypto|g' configure\n\n./configure \\")

p.write_text(s)
PY_PATCH_FFMPEG

MAKER_ABIS="${ABIS// /,}"

(
  cd "$FFMPEG_MAKER_DIR"

  export PATH="$HOME/.local/bin:$PATH"
  export CMAKE_POLICY_VERSION_MINIMUM=3.5

  # Strip the build machine's home path from compiled output (reproducibility / no path leaks).

  export CFLAGS="${CFLAGS:-} -ffile-prefix-map=$HOME=/usr/src/fermux -fdebug-prefix-map=$HOME=/usr/src/fermux -fmacro-prefix-map=$HOME=/usr/src/fermux"
  export CXXFLAGS="${CXXFLAGS:-} -ffile-prefix-map=$HOME=/usr/src/fermux -fdebug-prefix-map=$HOME=/usr/src/fermux -fmacro-prefix-map=$HOME=/usr/src/fermux"

  log "Building FFmpeg for ABIs: $MAKER_ABIS (all free + GPL libraries)"

  export EXTRA_BUILD_CONFIGURATION_FLAGS="${EXTRA_BUILD_CONFIGURATION_FLAGS:-} --enable-jni --enable-mediacodec"

  maker_args=(
    --enable-all-free
    --enable-all-gpl
    "--android-api-level=$API_LEVEL"
    "-abis=$MAKER_ABIS"
  )

  ANDROID_NDK_HOME="$TERMUX_NDK_ROOT" \
    ./ffmpeg-android-maker.sh "${maker_args[@]}"
)

verify_ffmpeg_for_abi() {
  local abi="$1"
  local bin_dir="$FFMPEG_MAKER_DIR/build/ffmpeg/$abi/bin"
  local ffmpeg_bin="$bin_dir/ffmpeg"
  local ffprobe_bin="$bin_dir/ffprobe"
  require_file "$ffmpeg_bin" "ffmpeg binary for $abi"
  require_file "$ffprobe_bin" "ffprobe binary for $abi"

  patchelf --set-rpath '$ORIGIN' "$ffmpeg_bin"
  patchelf --set-rpath '$ORIGIN' "$ffprobe_bin"
  file "$ffmpeg_bin"
  file "$ffprobe_bin"

  rm -rf "$OUT_DIR/ffmpeg/$abi"
  mkdir -p "$OUT_DIR/ffmpeg/$abi"
  cp "$ffmpeg_bin" "$OUT_DIR/ffmpeg/$abi/libffmpeg.so"
  cp "$ffprobe_bin" "$OUT_DIR/ffmpeg/$abi/libffprobe.so"
  cp -a "$FFMPEG_MAKER_DIR/build/ffmpeg/$abi/lib/." "$OUT_DIR/ffmpeg/$abi/" 2>/dev/null || true

  local staged="$OUT_DIR/ffmpeg/$abi"
  for exe in "$staged/libffmpeg.so" "$staged/libffprobe.so"; do
    readelf -d "$exe" | grep -E 'RUNPATH|RPATH' | grep -F '$ORIGIN' >/dev/null \
      || die "$(basename "$exe") for $abi has no \$ORIGIN RUNPATH"
  done

  for dep in libavdevice.so libavfilter.so libavformat.so libavcodec.so libswresample.so libswscale.so libavutil.so; do
    require_file "$staged/$dep" "$dep staged beside FFmpeg for $abi"
  done

  log "FFmpeg/ffprobe staged for $abi with self-contained \$ORIGIN runtime lookup"
}

for_each_abi verify_ffmpeg_for_abi

log "Reminder (doc section 99): a correct Android ELF does not imply HTTPS/TLS"
log "support. After packaging, run: adb shell '<libffmpeg.so path> -protocols' and"
log "confirm https/tls are listed before trusting this build for network use."
