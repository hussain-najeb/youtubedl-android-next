#!/usr/bin/env bash











set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo_config_once
require_dir "$TERMUX_PACKAGES_DIR" "run 00-setup-toolchains.sh first"

FULL_VER="$(python_full_version)"
MAJ_MIN="$(python_major_minor)"
log "Building against Termux python $FULL_VER (site-packages: python$MAJ_MIN)"


build_python_runtime_for_abi() {
  local abi="$1"
  local termux_arch; termux_arch="$(abi_termux_arch "$abi")"
  local runtime_prefix; runtime_prefix="$(termux_runtime_prefix "$abi")"

  log "Building Termux 'python' package for $abi ($termux_arch)"
  termux_build_package "$termux_arch" python

  
  
  
  local runtime_root; runtime_root="$(termux_runtime_root "$abi")"
  rm -rf "$runtime_root"
  mkdir -p "$runtime_root"

  local python_deb
  python_deb="$(find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -type f -name "python_*_${termux_arch}.deb" | sort | tail -1)"
  require_file "$python_deb" "python .deb for $termux_arch"

  local -a queue=("$python_deb")
  local -A seen=()
  local deb dep_line dep alt dep_deb
  while ((${#queue[@]})); do
    deb="${queue[0]}"
    queue=("${queue[@]:1}")
    [ -n "${seen[$deb]:-}" ] && continue
    seen[$deb]=1
    log "Extracting $(basename "$deb") into $runtime_root"
    dpkg-deb -x "$deb" "$runtime_root"

    dep_line="$(dpkg-deb -f "$deb" Depends 2>/dev/null || true)"
    [ -n "$dep_line" ] || continue
    IFS=',' read -ra _deps <<< "$dep_line"
    for dep in "${_deps[@]}"; do
      
      alt="${dep%%|*}"
      alt="${alt%%(*}"
      alt="${alt%%:*}"
      alt="$(printf '%s' "$alt" | xargs)"
      [ -n "$alt" ] || continue
      case "$alt" in
        libc|libdl|liblog|libm|android-support|command-not-found) continue ;;
      esac
      dep_deb="$(find "$TERMUX_PACKAGES_DIR/output" -maxdepth 1 -type f -name "${alt}_*_${termux_arch}.deb" | sort | tail -1)"
      if [ -n "$dep_deb" ]; then
        queue+=("$dep_deb")
      else
        warn "No built .deb found for dependency '$alt' ($abi); if it is not an Android system dependency, build/package it before runtime assembly"
      fi
    done
  done

  require_file "$runtime_prefix/bin/python${MAJ_MIN}" "python launcher for $abi"
}


inject_wheel_or_pkg() {
  
  
  local site="$1" name="$2" abi="$3"
  local whl=""
  if [ -d "$WHEELHOUSE_DIR/${name}-${abi}" ]; then
    whl="$(find "$WHEELHOUSE_DIR/${name}-${abi}" -maxdepth 1 -name '*.whl' | head -1)"
  fi
  if [ -n "${whl:-}" ]; then
    log "Injecting $name wheel for $abi: $(basename "$whl")"
    unzip -q -o "$whl" -d "$site"
    return
  fi
  local pkg_site="$WHEELHOUSE_DIR/${name}-${abi}-termux-pkg/data/data/com.termux/files/usr/lib/python${MAJ_MIN}/site-packages"
  if [ -d "$pkg_site" ]; then
    log "Injecting $name (Termux package) for $abi from $pkg_site"
    cp -a "$pkg_site"/. "$site"/
    return
  fi
  die "no wheel or extracted Termux package found for $name / $abi — run stage 20/40 first"
}

stage_python_bundle_for_abi() {
  local abi="$1"
  local runtime_prefix; runtime_prefix="$(termux_runtime_prefix "$abi")"
  local stage; stage="$(python_stage_dir "$abi")"
  local site; site="$(site_packages_dir "$abi")"

  log "Staging Python runtime for $abi -> $stage"
  rm -rf "$stage"
  mkdir -p "$stage/usr"
  cp -a "$runtime_prefix/lib" "$stage/usr/"

  
  mkdir -p "$stage/usr/share"
  if [ -d "$runtime_prefix/../share/terminfo" ]; then
    cp -a "$runtime_prefix/../share/terminfo" "$stage/usr/share/"
  fi

  mkdir -p "$site"
  inject_wheel_or_pkg "$site" cffi "$abi"
  
  
  
  local cffi_backend
  cffi_backend="$(find "$site" -maxdepth 1 -type f -name '_cffi_backend*.so' | head -1)"
  require_file "$cffi_backend" "_cffi_backend for $abi"

  if ! patchelf --print-needed "$cffi_backend" | grep -qx "libpython${MAJ_MIN}.so"; then
    log "Adding DT_NEEDED libpython${MAJ_MIN}.so to $(basename "$cffi_backend")"
    patchelf --add-needed "libpython${MAJ_MIN}.so" "$cffi_backend"
  fi

  inject_wheel_or_pkg "$site" curl_cffi "$abi"
  
  
  local curl_cffi_wrapper
  curl_cffi_wrapper="$site/curl_cffi/_wrapper.abi3.so"
  require_file "$curl_cffi_wrapper" "curl_cffi wrapper for $abi"

  if ! patchelf --print-needed "$curl_cffi_wrapper" | grep -qx "libpython${MAJ_MIN}.so"; then
    log "Adding DT_NEEDED libpython${MAJ_MIN}.so to curl_cffi/_wrapper.abi3.so"
    patchelf --add-needed "libpython${MAJ_MIN}.so" "$curl_cffi_wrapper"
  fi


  log "Installing pure-Python extras (mutagen, certifi) for $abi"
  python3 -m pip install --target "$site" --no-deps \
    "mutagen==$MUTAGEN_VERSION" \
    "certifi==$CERTIFI_VERSION"

  require_file "$site/certifi/cacert.pem" "certifi CA bundle for $abi (doc section 33)"
  require_dir "$stage/usr/lib/ossl-modules" "OpenSSL 3 modules for $abi (doc section 34)"
}


package_python_for_abi() {
  local abi="$1"
  local runtime_prefix; runtime_prefix="$(termux_runtime_prefix "$abi")"
  local stage; stage="$(python_stage_dir "$abi")"

  
  relocate_termux_elf_runpaths "$stage"
  verify_no_termux_elf_runpaths "$stage"

  local py_out_dir="$OUT_DIR/python/$abi"
  local zip_out="$py_out_dir/libpython-${FULL_VER}-${abi}.zip.so"
  local launcher_out="$py_out_dir/libpython-${FULL_VER}-${abi}.so"
  rm -rf "$py_out_dir"
  mkdir -p "$py_out_dir"

  log "Zipping runtime for $abi -> $zip_out (symlinks preserved: zip -y)"
  rm -f "$zip_out"
  (cd "$stage" && zip -y -r "$zip_out" usr >/dev/null)

  log "Copying interpreter launcher for $abi -> $launcher_out"
  cp "$runtime_prefix/bin/python${MAJ_MIN}" "$launcher_out"

  file "$launcher_out"
  readelf -d "$launcher_out" | grep NEEDED || true
  unzip -l "$zip_out" | tail -5

  log "$abi packaged: $zip_out + $launcher_out"
}

build_all_for_abi() {
  local abi="$1"
  build_python_runtime_for_abi "$abi"
  stage_python_bundle_for_abi "$abi"
  package_python_for_abi "$abi"
}

for_each_abi build_all_for_abi
log "Python runtime build complete for: $ABIS"
log "Artifacts in: $OUT_DIR/python/<abi>/libpython-${FULL_VER}-<abi>.{so,zip.so}"
