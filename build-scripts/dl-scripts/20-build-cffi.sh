#!/usr/bin/env bash























set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once

fetch_cffi_source() {
  local src_url="https://files.pythonhosted.org/packages/source/c/cffi/cffi-${CFFI_VERSION}.tar.gz"
  local archive="$CFFI_SRC_DIR/cffi-$CFFI_VERSION.tar.gz"

  if [ -d "$CFFI_SRC_DIR/cffi-$CFFI_VERSION" ]; then
    return
  fi

  require_cmd curl
  require_cmd sha256sum
  mkdir -p "$CFFI_SRC_DIR"
  curl -LfsS "$src_url" -o "$archive"
  printf '%s  %s\n' "$CFFI_SHA256" "$archive" | sha256sum -c - \
    || die "CFFI $CFFI_VERSION source SHA256 mismatch"
  tar -C "$CFFI_SRC_DIR" -xf "$archive"
}


patch_cffi_source_for_fermux() {
  local setup_py="$CFFI_SRC_DIR/cffi-$CFFI_VERSION/setup.py"
  require_file "$setup_py" "CFFI setup.py"

  if grep -q 'FERMUX_LIBFFI_PREFIX' "$setup_py"; then
    return
  fi

  python3 - "$setup_py" <<'PY_CFFI_PATCH'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

old = """\
else:
    use_pkg_config()
    ask_supports_thread()
    ask_supports_sync_synchronize()
"""

new = """\
else:
    fermux_libffi_prefix = os.environ.get("FERMUX_LIBFFI_PREFIX")
    if fermux_libffi_prefix:
        include_dirs[:] = [os.path.join(fermux_libffi_prefix, "include")]
        library_dirs[:] = [os.path.join(fermux_libffi_prefix, "lib")]
        libraries[:] = ["ffi"]
    else:
        use_pkg_config()

    ask_supports_thread()
    ask_supports_sync_synchronize()
"""

if old not in s:
    raise SystemExit(
        "ERROR: pinned CFFI setup.py no longer matches Fermux patch context"
    )

p.write_text(s.replace(old, new, 1))
PY_CFFI_PATCH

  grep -q 'FERMUX_LIBFFI_PREFIX' "$setup_py" \
    || die "failed to apply Fermux CFFI libffi-prefix patch"
}


build_cffi_cibuildwheel() {
  local abi="$1" cibw_arch="$2"
  local runtime_prefix; runtime_prefix="$(termux_runtime_prefix "$abi")"
  require_dir "$runtime_prefix/lib/pkgconfig" "run 10-build-libffi.sh first for $abi"
  patch_cffi_source_for_fermux

  log "Building CFFI wheel for $abi via cibuildwheel ($cibw_arch)"
  (
    cd "$CFFI_SRC_DIR/cffi-$CFFI_VERSION"


    export CIBW_ENVIRONMENT_ANDROID="FERMUX_LIBFFI_PREFIX=$runtime_prefix AUDITWHEEL_LD_LIBRARY_PATH=$runtime_prefix/lib"

    python3 -m cibuildwheel \
      --platform android \
      --archs "$cibw_arch" \
      --output-dir "$WHEELHOUSE_DIR/cffi-$abi"
  )

  local wheel
  wheel="$(find "$WHEELHOUSE_DIR/cffi-$abi" -maxdepth 1 -name "cffi-${CFFI_VERSION}-*.whl" | head -1)"
  require_file "$wheel" "CFFI wheel for $abi"

  
  
  
  local repair_root="$WORK_ROOT/cffi-$abi-wheel-repair"
  rm -rf "$repair_root"
  mkdir -p "$repair_root/unpacked" "$repair_root/out"

  unzip -q "$wheel" -d "$repair_root/unpacked"

  local repair_backend
  repair_backend="$(find "$repair_root/unpacked" -name '_cffi_backend*.so' -type f | head -1)"
  require_file "$repair_backend" "_cffi_backend before wheel repair for $abi"

  mkdir -p "$repair_root/unpacked/cffi.libs"
  cp "$runtime_prefix/lib/libffi.so" "$repair_root/unpacked/cffi.libs/libffi.so"

  patchelf --set-rpath '$ORIGIN/cffi.libs' "$repair_backend"

  rm -f "$wheel"
  python3 -m wheel pack     "$repair_root/unpacked"     --dest-dir "$repair_root/out"

  cp "$repair_root/out/"*.whl "$WHEELHOUSE_DIR/cffi-$abi/"

  wheel="$(find "$WHEELHOUSE_DIR/cffi-$abi" -maxdepth 1 -name "cffi-${CFFI_VERSION}-*.whl" | head -1)"
  require_file "$wheel" "repaired CFFI wheel for $abi"

  log "Verifying bundled libffi in $wheel"
  unzip -l "$wheel" | grep -E 'libffi|cffi\.libs|_cffi_backend' \
    || die "wheel for $abi does not look like it bundled libffi — inspect manually"

  local verify_dir="$WORK_ROOT/cffi-$abi-wheel-verify"
  rm -rf "$verify_dir"
  mkdir -p "$verify_dir"
  unzip -q "$wheel" -d "$verify_dir"
  local backend
  backend="$(find "$verify_dir" -name '_cffi_backend*.so' -type f | head -1)"
  require_file "$backend" "_cffi_backend in repaired wheel for $abi"
  if readelf -d "$backend" | grep -q 'Shared library: \[libffi'; then
    readelf -d "$backend" | grep -E 'RUNPATH|RPATH' >/dev/null \
      || die "_cffi_backend for $abi depends on libffi but has no runtime search path"
  fi
}





generate_termux_cffi_package() {
  local pkg_dir="$TERMUX_PACKAGES_DIR/packages/python-cffi-android"
  local src_url="https://files.pythonhosted.org/packages/source/c/cffi/cffi-${CFFI_VERSION}.tar.gz"
  
  
  
  [ -n "$CFFI_SHA256" ] || die "CFFI_SHA256 is empty"

  mkdir -p "$pkg_dir"
  cat > "$pkg_dir/build.sh" <<EOF


TERMUX_PKG_HOMEPAGE="https://cffi.readthedocs.io/"
TERMUX_PKG_DESCRIPTION="Foreign Function Interface for Python calling C code"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_VERSION=$CFFI_VERSION
TERMUX_PKG_SRCURL=$src_url
TERMUX_PKG_SHA256=$CFFI_SHA256
TERMUX_PKG_DEPENDS="python, python-pip, libffi"
TERMUX_PKG_BUILD_DEPENDS="libffi"

termux_step_make() {
        termux_setup_python_pip
        cd "\$TERMUX_PKG_SRCDIR"

        cross-pip wheel -v --no-build-isolation --no-deps \
                -w "\$TERMUX_PKG_TMPDIR/wheel" .
}

termux_step_make_install() {
	local site="\$TERMUX_PREFIX/lib/python$(python_major_minor)/site-packages"
	mkdir -p "\$site"
	unzip -o -q "\$TERMUX_PKG_TMPDIR"/wheel/cffi-*.whl -d "\$site"
	find "\$site" -maxdepth 2 -name '_cffi_backend*.so' -print -quit | grep -q . \\
		|| { echo 'CFFI build did not install _cffi_backend' >&2; return 1; }
}
EOF
  log "Wrote Docker-visible Termux package recipe: $pkg_dir/build.sh"
}

build_cffi_termux_fallback() {
  local abi="$1"
  local termux_arch; termux_arch="$(abi_termux_arch "$abi")"

  log "Building CFFI for $abi ($termux_arch) with Termux cross-Python"
  generate_termux_cffi_package
  termux_build_package "$termux_arch" python-cffi-android

  local deb
  deb="$(find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -name "python-cffi-android_*_${termux_arch}.deb" | sort | tail -1)"
  require_file "$deb" "python-cffi-android .deb for $termux_arch"
  local extract="$WHEELHOUSE_DIR/cffi-$abi-termux-pkg"
  rm -rf "$extract"
  mkdir -p "$extract"
  dpkg-deb -x "$deb" "$extract"
  local pkg_site="$extract/data/data/com.termux/files/usr/lib/python$(python_major_minor)/site-packages"
  require_dir "$pkg_site" "CFFI site-packages for $abi"
  local backend
  backend="$(find "$pkg_site" -name '_cffi_backend*.so' -type f -print -quit)"
  require_file "$backend" "_cffi_backend for $abi"

  
  
  local runtime_prefix; runtime_prefix="$(termux_runtime_prefix "$abi")"
  local libs_dir="$pkg_site/cffi.libs"
  mkdir -p "$libs_dir"
  find "$runtime_prefix/lib" -maxdepth 1 -name 'libffi.so*' -exec cp -a {} "$libs_dir/" \;
  find "$libs_dir" -name 'libffi.so*' -print -quit | grep -q . \
    || die "could not bundle libffi beside 32-bit CFFI for $abi"

  require_cmd patchelf
  patchelf --set-rpath '$ORIGIN/cffi.libs' "$backend"
  readelf -d "$backend" | grep -E 'RUNPATH|RPATH' | grep -F '$ORIGIN/cffi.libs' >/dev/null \
    || die "failed to set self-contained CFFI RUNPATH for $abi"

  log "Extracted CFFI for $abi with bundled libffi + \$ORIGIN/cffi.libs RUNPATH"
}

build_cffi_for_abi() {
  local abi="$1"
  local cibw_arch; cibw_arch="$(abi_cibw_arch "$abi")"
  if [ -n "$cibw_arch" ]; then
    build_cffi_cibuildwheel "$abi" "$cibw_arch"
  else
    build_cffi_termux_fallback "$abi"
  fi
}

fetch_cffi_source
for_each_abi build_cffi_for_abi
log "CFFI build complete for: $ABIS"
