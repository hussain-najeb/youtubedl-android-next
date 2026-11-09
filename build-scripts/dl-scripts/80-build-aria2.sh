#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once

RECIPE_SRC="$SCRIPT_DIR/aria2-next"
RECIPE_DST="$TERMUX_PACKAGES_DIR/packages/aria2-next"



ARIA2_DEP_GLOBS=(
  "libc++_*"
)

install_recipe() {
  require_file "$RECIPE_SRC/build.sh" "aria2-next build.sh"
  require_file "$RECIPE_SRC/0001-android-multi-arch.patch" "aria2-next patch"
  mkdir -p "$RECIPE_DST"
  cp -f "$RECIPE_SRC/build.sh" "$RECIPE_SRC/0001-android-multi-arch.patch" "$RECIPE_DST/"
}

build_aria2_for_abi() {
  local abi="$1"
  local termux_arch; termux_arch="$(abi_termux_arch "$abi")"

  log "Building Termux 'aria2-next' package for $abi ($termux_arch)"
  
  
  
  termux_build_package "$termux_arch" aria2-next -f

  local extract_root="$WORK_ROOT/aria2-$abi-extract"
  rm -rf "$extract_root"
  mkdir -p "$extract_root"

  
  local next_deb
  next_deb="$(find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -name "aria2-next_*_${termux_arch}.deb" \
    -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)"
  require_file "$next_deb" "aria2-next .deb for $termux_arch"
  dpkg-deb -x "$next_deb" "$extract_root"

  local glob deb
  for glob in "${ARIA2_DEP_GLOBS[@]}"; do
    for deb in "$TERMUX_PACKAGES_DIR"/output/${glob}_"${termux_arch}".deb; do
      [ -e "$deb" ] || continue
      dpkg-deb -x "$deb" "$extract_root"
    done
  done

  
  local ca_deb
  ca_deb="$(find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -name 'ca-certificates_*_all.deb' \
    -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)"
  if [ -n "$ca_deb" ]; then
    dpkg-deb -x "$ca_deb" "$extract_root"
  else
    log "WARNING: no ca-certificates .deb in output/; build it (termux build ca-certificates) or HTTPS will fail"
  fi

  local termux_root="$extract_root/data/data/com.termux/files/usr"
  require_file "$termux_root/bin/aria2-next" "aria2-next binary for $abi"
  require_file "$termux_root/etc/tls/cert.pem" "CA bundle (etc/tls/cert.pem) for $abi"

  local bundle="$WORK_ROOT/aria2-$abi-bundle"
  rm -rf "$bundle"
  mkdir -p "$bundle/usr/bin" "$bundle/usr/lib" "$bundle/usr/etc/tls"
  cp "$termux_root/bin/aria2-next" "$bundle/usr/bin/aria2c.real"
  chmod 755 "$bundle/usr/bin/aria2c.real"

  
  local so
  find "$termux_root/lib" -maxdepth 1 \( -type f -o -type l \) -name '*.so*' -print0 |
    while IFS= read -r -d '' so; do
      cp -a "$so" "$bundle/usr/lib/"
    done
  require_file "$bundle/usr/lib/libc++_shared.so" "libc++_shared.so for $abi"

  cp -a "$termux_root/etc/tls/cert.pem" "$bundle/usr/etc/tls/cert.pem"

  
  
  cat > "$bundle/usr/bin/aria2c" <<'EOF_ARIA2_WRAPPER'
#!/system/bin/sh
set -eu
BIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
USR_DIR="$(CDPATH= cd -- "$BIN_DIR/.." && pwd)"
export LD_LIBRARY_PATH="$USR_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PREFIX="$USR_DIR"
exec "$BIN_DIR/aria2c.real" "$@"
EOF_ARIA2_WRAPPER
  chmod 755 "$bundle/usr/bin/aria2c"

  local zip_out="$OUT_DIR/aria2/$abi/libaria2-${abi}.zip.so"
  mkdir -p "$(dirname "$zip_out")"
  rm -f "$zip_out"
  (cd "$bundle" && zip -y -r "$zip_out" usr >/dev/null)
  log "aria2-next packaged for $abi: $zip_out"
}

build_ca_certificates() {
  
  
  if ! find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -name 'ca-certificates_*_all.deb' 2>/dev/null | grep -q .; then
    log "Building Termux 'ca-certificates' (arch-independent)"
    termux_build_package aarch64 ca-certificates
  fi
}

install_recipe
build_ca_certificates
for_each_abi build_aria2_for_abi

log "Runtime verification, on-device per ABI:"
log '  ARIA2_ROOT=/path/to/extracted/aria2/usr'
log '  $ARIA2_ROOT/bin/aria2c --version'
log '  $ARIA2_ROOT/bin/aria2c https://example.com/ -d /tmp   # checks TLS'
log 'The bundled launcher sets LD_LIBRARY_PATH and PREFIX itself.'
