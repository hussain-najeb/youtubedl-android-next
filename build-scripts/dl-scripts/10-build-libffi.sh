#!/usr/bin/env bash














set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once
require_dir "$TERMUX_PACKAGES_DIR" "run 00-setup-toolchains.sh first"

build_libffi_for_abi() {
  local abi="$1"
  local termux_arch; termux_arch="$(abi_termux_arch "$abi")"
  local runtime_prefix; runtime_prefix="$(termux_runtime_prefix "$abi")"

  log "Building Termux 'libffi' package for $abi (Termux arch: $termux_arch)"
  termux_build_package "$termux_arch" libffi

  local deb
  deb="$(find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -name "libffi_*_${termux_arch}.deb" | sort | tail -1)"
  require_file "$deb" "libffi .deb for $termux_arch"

  local runtime_root; runtime_root="$(termux_runtime_root "$abi")"
  rm -rf "$runtime_root"
  mkdir -p "$runtime_root"
  dpkg-deb -x "$deb" "$runtime_root"

  require_file "$runtime_prefix/include/ffi.h" "libffi headers for $abi"
  local libffi_so
  libffi_so="$(find "$runtime_prefix/lib" -maxdepth 1 -name 'libffi.so*' -type f | head -1)"
  require_file "$libffi_so" "libffi.so for $abi"
  file "$libffi_so" | grep -q 'ELF' || die "libffi for $abi is not an ELF shared object"
  readelf -d "$libffi_so" | grep -q '(SONAME)' \
    || die "libffi for $abi has no SONAME"

  local unversioned="$runtime_prefix/lib/libffi.so"
  if [ -L "$unversioned" ]; then
    local target
    target="$(readlink "$unversioned")"
    [ -e "$runtime_prefix/lib/$target" ] \
      || die "libffi.so symlink for $abi points to missing target: $target"
  elif [ ! -f "$unversioned" ]; then
    warn "No unversioned libffi.so for $abi; consumers must link by SONAME/pkg-config"
  fi
  log "libffi ready for $abi: $runtime_prefix (validated ELF + SONAME)"
}

for_each_abi build_libffi_for_abi
log "libffi build complete for: $ABIS"
