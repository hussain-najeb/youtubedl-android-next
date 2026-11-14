#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once

fetch_curl_cffi_source() {
  if [ ! -d "$CURL_CFFI_SRC_DIR/.git" ]; then
    rm -rf "$CURL_CFFI_SRC_DIR"
    git clone --no-checkout --depth 1 https://github.com/lexiforest/curl_cffi.git "$CURL_CFFI_SRC_DIR"
  fi
  git -C "$CURL_CFFI_SRC_DIR" fetch --depth 1 origin "$CURL_CFFI_COMMIT"
  git -C "$CURL_CFFI_SRC_DIR" checkout --force --detach "$CURL_CFFI_COMMIT"
  git -C "$CURL_CFFI_SRC_DIR" reset --hard "$CURL_CFFI_COMMIT"
  [ "$(git -C "$CURL_CFFI_SRC_DIR" rev-parse HEAD)" = "$CURL_CFFI_COMMIT" ] \
    || die "curl_cffi checkout does not match pinned commit $CURL_CFFI_COMMIT"
}

verify_curl_cffi_android_cross_abi_support() {
  python3 - "$CURL_CFFI_SRC_DIR/libs.json" "$CURL_CFFI_SRC_DIR/scripts/build.py" <<'PY_VERIFY_ANDROID_ABIS'
import json
from pathlib import Path
import sys

metadata = json.loads(Path(sys.argv[1]).read_text())
required = {
    ("aarch64", 64, "aarch64"),
    ("x86_64", 64, "x86_64"),
    ("armv7l", 32, "armv7"),
}
found = {
    (entry.get("machine"), entry.get("pointer_size"), entry.get("arch"))
    for entry in metadata
    if entry.get("system") == "Android" and entry.get("libc") == "android"
}
missing = sorted(required - found)
if missing:
    raise SystemExit(f"curl_cffi Android ABI metadata missing upstream targets: {missing}")

build_script = Path(sys.argv[2]).read_text()
required_build_tokens = (
    'machine = os.environ.get("CURL_CFFI_TARGET_MACHINE", uname.machine)',
    '"CURL_CFFI_TARGET_POINTER_SIZE"',
    'arch["machine"] == machine',
    'arch["pointer_size"] == pointer_size',
)
for token in required_build_tokens:
    if token not in build_script:
        raise SystemExit(
            f"curl_cffi scripts/build.py is missing upstream Android target logic: {token}"
        )
PY_VERIFY_ANDROID_ABIS
  log "curl_cffi upstream Android cross-ABI support verified"
}

curl_impersonate_lib_dir() {
  local abi="$1"
  local build_dir="$WORK_ROOT/curl-impersonate-build-$abi"
  local install_dir="$WORK_ROOT/curl-impersonate-install-$abi"
  local archive
  archive="$(find "$build_dir" "$install_dir" -type f -name 'libcurl-impersonate*.a' 2>/dev/null | head -1)"
  require_file "$archive" "libcurl-impersonate.a for $abi (run 30-build-curl-impersonate.sh)"
  dirname "$archive"
}

curl_impersonate_deps_dir() {
  local abi="$1"
  local build_dir="$WORK_ROOT/curl-impersonate-build-$abi"
  
  
  if [ -d "$build_dir/deps/install/lib" ]; then
    echo "$build_dir/deps/install/lib"
    return
  fi
  local install_dir="$WORK_ROOT/curl-impersonate-install-$abi/lib"
  require_dir "$install_dir" "curl-impersonate dependency libraries for $abi"
  echo "$install_dir"
}

ensure_curl_cffi_static_deps_patch() {
  local build_py="$CURL_CFFI_SRC_DIR/scripts/build.py"
  require_file "$build_py" "curl_cffi scripts/build.py"

  python3 - "$build_py" <<'PY_PATCH_STATIC_DEPS'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()


if 'deps_dir = os.environ.get("IMPERSONATE_DEPS_DIR")' in s:
    raise SystemExit(0)

needle = '''static_libs = get_curl_archives()
extra_link_args = []
'''

replacement = '''static_libs = get_curl_archives()

deps_dir = os.environ.get("IMPERSONATE_DEPS_DIR")
dependency_archives = []

if deps_dir:
    deps_path = Path(os.path.expanduser(deps_dir))
    if not deps_path.is_dir():
        raise RuntimeError(
            f"IMPERSONATE_DEPS_DIR does not exist: {deps_path}"
        )

    dependency_archives = sorted(
        str(path)
        for path in deps_path.glob("*.a")
    )

    if is_static and is_android and not dependency_archives:
        raise RuntimeError(
            f"No static dependency archives found in {deps_path}"
        )

extra_link_args = []
'''

if needle not in s:
    raise SystemExit(
        "curl_cffi static_libs/extra_link_args block not found"
    )

s = s.replace(needle, replacement, 1)

old = '''        extra_link_args = [
            "-Wl,--whole-archive",
            static_libs[0],
            "-Wl,--no-whole-archive",
        ]
'''

new = '''        extra_link_args = [
            "-Wl,--whole-archive",
            static_libs[0],
            *dependency_archives,
            "-Wl,--no-whole-archive",
        ]
'''

if old not in s:
    raise SystemExit("curl_cffi upstream Android/Linux static-link block not found")

p.write_text(s.replace(old, new, 1))
PY_PATCH_STATIC_DEPS
}


fetch_curl_cffi_official_wheel() {
  local abi="$1"
  local dest="$WHEELHOUSE_DIR/curl_cffi-$abi"
  mkdir -p "$dest"
  log "Downloading official curl_cffi Android wheel for $abi" >&2
  local py_majmin; py_majmin="$(python_major_minor | tr -d '.')"
  (
    cd "$dest"
    python3 -m pip download --no-deps --only-binary=:all: \
      --platform "android_${API_LEVEL}_arm64_v8a" \
      --python-version "$(python_major_minor)" \
      --implementation cp \
      --abi "cp${py_majmin}" \
      "curl_cffi==$CURL_CFFI_VERSION"
  ) >&2
  find "$dest" -name '*.whl' | head -1
}


build_curl_cffi_cibuildwheel() {
  local abi="$1" cibw_arch="$2"
  local impersonate_lib_dir; impersonate_lib_dir="$(curl_impersonate_lib_dir "$abi")"

  log "Building curl_cffi wheel for $abi via cibuildwheel ($cibw_arch)" >&2
  (
    cd "$CURL_CFFI_SRC_DIR"
    export IMPERSONATE_BUILD_DIR="$impersonate_lib_dir"
    export IMPERSONATE_DEPS_DIR="$(curl_impersonate_deps_dir "$abi")"
    export IMPERSONATE_LINK_TYPE=static
    export CIBW_TEST_SKIP="cp*-android_${cibw_arch}"
    rm -rf "$WHEELHOUSE_DIR/curl_cffi-$abi"
    python3 -m cibuildwheel \
      --platform android \
      --archs "$cibw_arch" \
      --output-dir "$WHEELHOUSE_DIR/curl_cffi-$abi"
  ) >&2
  find "$WHEELHOUSE_DIR/curl_cffi-$abi" -name '*.whl' | head -1
}





generate_termux_curl_cffi_package() {
  local abi="$1" machine="$2" arch="$3"
  local impersonate_lib_dir; impersonate_lib_dir="$(curl_impersonate_lib_dir "$abi")"
  local impersonate_deps_dir; impersonate_deps_dir="$(curl_impersonate_deps_dir "$abi")"

  local pkg_dir="$TERMUX_PACKAGES_DIR/packages/python-curl-cffi-android"
  local vendor="$pkg_dir/fermux-vendor"
  rm -rf "$vendor"
  mkdir -p "$vendor/curl" "$vendor/deps"

  
  cp "$CURL_CFFI_SRC_DIR/libs.json" "$vendor/libs.json"

  local archive
  archive="$(find "$impersonate_lib_dir" -maxdepth 1 -type f -name 'libcurl-impersonate*.a' | head -1)"
  require_file "$archive" "curl-impersonate archive for $abi"
  
  cp "$archive" "$vendor/curl/libcurl-impersonate.a"

  require_dir "$WORK_ROOT/curl-impersonate-install-$abi/include/curl" \
    "curl headers for $abi"
  cp -a "$WORK_ROOT/curl-impersonate-install-$abi/include" "$vendor/curl/"

  find "$impersonate_deps_dir" -maxdepth 1 -type f -name '*.a' -exec cp -a {} "$vendor/deps/" \;

  
  
  
  local source_tar="$vendor/curl_cffi-${CURL_CFFI_VERSION}-fermux.tar.gz"
  tar --exclude='.git' -C "$CURL_CFFI_SRC_DIR" -czf "$source_tar" .
  local src_sha; src_sha="$(sha256sum "$source_tar" | awk '{print $1}')"

  cat > "$pkg_dir/build.sh" <<EOF_BUILD


TERMUX_PKG_HOMEPAGE="https://github.com/lexiforest/curl_cffi"
TERMUX_PKG_DESCRIPTION="Python binding for curl-impersonate via cffi"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_VERSION=$CURL_CFFI_VERSION
TERMUX_PKG_SRCURL="file://\$TERMUX_PKG_BUILDER_DIR/fermux-vendor/curl_cffi-${CURL_CFFI_VERSION}-fermux.tar.gz"
TERMUX_PKG_SHA256=$src_sha
TERMUX_PKG_DEPENDS="python, python-pip, python-cffi-android, openssl"

termux_step_post_get_source() {
    cp "\$TERMUX_PKG_BUILDER_DIR/fermux-vendor/libs.json" "\$TERMUX_PKG_SRCDIR/libs.json"
}

termux_step_make() {
    termux_setup_python_pip
    cd "\$TERMUX_PKG_SRCDIR"

    unset PYTHONPATH
    cross-pip uninstall -y cffi pycparser || true
    build-pip install --upgrade 'cffi==2.1.1'
    cross-pip install --no-deps wheel

    export IMPERSONATE_BUILD_DIR="\$TERMUX_PKG_BUILDER_DIR/fermux-vendor/curl"
    export IMPERSONATE_DEPS_DIR="\$TERMUX_PKG_BUILDER_DIR/fermux-vendor/deps"
    export IMPERSONATE_LINK_TYPE=static

    
    
    export CIBW_PLATFORM=android

    export CURL_CFFI_TARGET_MACHINE="$machine"
    export CURL_CFFI_TARGET_POINTER_SIZE=32
    export LDFLAGS="\${LDFLAGS} -lm"

    cross-python setup.py bdist_wheel --dist-dir "\$TERMUX_PKG_TMPDIR/wheel"
}

termux_step_make_install() {
    local site="\$TERMUX_PREFIX/lib/python$(python_major_minor)/site-packages"
    mkdir -p "\$site"
    unzip -o -q "\$TERMUX_PKG_TMPDIR"/wheel/curl_cffi-*.whl -d "\$site"
    [ -d "\$site/curl_cffi" ] || { echo 'curl_cffi package missing after install' >&2; return 1; }
}
EOF_BUILD
  log "Wrote Docker-visible curl_cffi Termux recipe and vendored ABI inputs for $abi"
}

build_curl_cffi_termux_fallback() {
  local abi="$1" machine="$2" arch="$3"
  local termux_arch; termux_arch="$(abi_termux_arch "$abi")"

  log "Building curl_cffi for $abi ($termux_arch) with Termux cross-Python"
  generate_termux_curl_cffi_package "$abi" "$machine" "$arch"
  (
    cd "$TERMUX_PACKAGES_DIR"
    export TERMUX_JAVA_HOME TERMUX_BUILDER_IMAGE_NAME CONTAINER_NAME TERMUX_DOCKER_RUN_EXTRA_ARGS
    export JAVA_HOME="$TERMUX_JAVA_HOME"
    ./scripts/run-docker.sh ./build-package.sh -f -a "$termux_arch" python-curl-cffi-android
  )

  local deb
  deb="$(find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -name "python-curl-cffi-android_*_${termux_arch}.deb" | sort | tail -1)"
  require_file "$deb" "python-curl-cffi-android .deb for $termux_arch"
  local extract="$WHEELHOUSE_DIR/curl_cffi-$abi-termux-pkg"
  rm -rf "$extract"
  mkdir -p "$extract"
  dpkg-deb -x "$deb" "$extract"
  local pkg_site="$extract/data/data/com.termux/files/usr/lib/python$(python_major_minor)/site-packages"
  require_dir "$pkg_site/curl_cffi" "curl_cffi site-package for $abi"
  log "Extracted and verified Termux-built curl_cffi for $abi"
}

publish_curl_cffi_wheel() {
  local abi="$1" wheel="$2"
  local out="$OUT_DIR/curl_cffi/$abi"
  rm -rf "$out"
  mkdir -p "$out"
  cp "$wheel" "$out/"
  log "curl_cffi published for $abi -> $out/$(basename "$wheel")"
}

publish_curl_cffi_termux_pkg() {
  local abi="$1"
  local termux_arch; termux_arch="$(abi_termux_arch "$abi")"
  local out="$OUT_DIR/curl_cffi/$abi"
  local deb
  deb="$(find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -name "python-curl-cffi-android_*_${termux_arch}.deb" | sort | tail -1)"
  require_file "$deb" "python-curl-cffi-android .deb for $termux_arch"
  rm -rf "$out"
  mkdir -p "$out"
  cp "$deb" "$out/"
  # The extracted site-packages tree (what stage 50 actually injects) as a plain tarball.
  local pkg_site="$WHEELHOUSE_DIR/curl_cffi-$abi-termux-pkg/data/data/com.termux/files/usr/lib/python$(python_major_minor)/site-packages"
  require_dir "$pkg_site/curl_cffi" "extracted curl_cffi for $abi"
  tar -C "$pkg_site" -czf "$out/curl_cffi-${CURL_CFFI_VERSION}-${abi}-site-packages.tar.gz" curl_cffi
  log "curl_cffi (Termux package) published for $abi -> $out"
}

build_curl_cffi_for_abi() {
  local abi="$1"
  case "$abi" in
    arm64-v8a)
      local wheel
      if [ "$ARM64_USE_OFFICIAL_CURL_CFFI" = "1" ]; then
        wheel="$(fetch_curl_cffi_official_wheel "$abi")"
        require_file "$wheel" "curl_cffi official wheel for $abi"
      else
        wheel="$(build_curl_cffi_cibuildwheel "$abi" arm64_v8a)"
        require_file "$wheel" "curl_cffi built wheel for $abi"
      fi
      log "curl_cffi for $abi: $wheel"
      publish_curl_cffi_wheel "$abi" "$wheel"
      ;;
    x86_64)
      local wheel; wheel="$(build_curl_cffi_cibuildwheel "$abi" x86_64)"
      require_file "$wheel" "curl_cffi built wheel for $abi"
      log "curl_cffi for $abi: $wheel"
      publish_curl_cffi_wheel "$abi" "$wheel"
      ;;
    armeabi-v7a)
      build_curl_cffi_termux_fallback "$abi" armv7l armv7
      publish_curl_cffi_termux_pkg "$abi"
      ;;
    *) die "unknown ABI: $abi" ;;
  esac
}

fetch_curl_cffi_source
verify_curl_cffi_android_cross_abi_support
ensure_curl_cffi_static_deps_patch
for_each_abi build_curl_cffi_for_abi
