#!/usr/bin/env bash











set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
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

  local site_dir="$stage/usr/lib/python${MAJ_MIN}/site-packages"
  local needed_lib

  # Deduplicate auditwheel-bundled libc++_shared-*.so and libffi-*.so by pointing
  # curl_cffi and cffi at the shared libc++_shared.so (in libffmpeg.tar.xz.so) and
  # libffi.so (in usr/lib) already on LD_LIBRARY_PATH.
  if [ -f "$site_dir/curl_cffi/_wrapper.abi3.so" ]; then
    while IFS= read -r needed_lib; do
      case "$needed_lib" in
        libc++_shared-*.so)
          patchelf --replace-needed "$needed_lib" libc++_shared.so "$site_dir/curl_cffi/_wrapper.abi3.so"
          ;;
      esac
    done < <(patchelf --print-needed "$site_dir/curl_cffi/_wrapper.abi3.so")
  fi
  rm -rf "$site_dir/curl_cffi.libs"

  local cffi_so
  cffi_so="$(find "$site_dir" -maxdepth 1 -type f -name '_cffi_backend*.so' | head -1)"
  if [ -n "${cffi_so:-}" ] && [ -f "$cffi_so" ]; then
    while IFS= read -r needed_lib; do
      case "$needed_lib" in
        libffi-*.so)
          patchelf --replace-needed "$needed_lib" libffi.so "$cffi_so"
          ;;
      esac
    done < <(patchelf --print-needed "$cffi_so")
  fi
  rm -rf "$site_dir/cffi.libs"

  local strip_bin="$TERMUX_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
  if [ -x "$strip_bin" ]; then
    if [ -f "$site_dir/curl_cffi/_wrapper.abi3.so" ]; then
      "$strip_bin" --strip-unneeded "$site_dir/curl_cffi/_wrapper.abi3.so"
    fi
    if [ -n "${cffi_so:-}" ] && [ -f "$cffi_so" ]; then
      "$strip_bin" --strip-unneeded "$cffi_so"
    fi
  fi

  local py_lib_dir="$stage/usr/lib/python${MAJ_MIN}"
  # Remove unused duplicate SQLite copy, interactive terminal/db libs, and build/test leftovers.
  rm -f \
    "$stage"/usr/lib/libsqlite3.[0-9]*.so \
    "$stage"/usr/lib/libncursesw.so* \
    "$stage"/usr/lib/libformw.so* \
    "$stage"/usr/lib/libmenuw.so* \
    "$stage"/usr/lib/libpanelw.so* \
    "$stage"/usr/lib/libreadline.so* \
    "$stage"/usr/lib/libhistory.so* \
    "$stage"/usr/lib/libgdbm*.so*
  rm -rf \
    "$stage/usr/share/terminfo" \
    "$stage/usr/lib/pkgconfig" \
    "$stage/usr/lib/cmake" \
    "$py_lib_dir/unittest" \
    "$py_lib_dir/pydoc_data" \
    "$py_lib_dir/_pyrepl" \
    "$py_lib_dir"/config-*
  find "$py_lib_dir/lib-dynload" -maxdepth 1 -type f \
    \( -name '_test*.so' -o -name '_ctypes_test*.so' -o -name '_xxtestfuzz*.so' \
       -o -name '_curses*.so' -o -name 'readline*.so' -o -name '_gdbm*.so' \) \
    -delete 2>/dev/null || true
  find "$py_lib_dir" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

  # C1: remove libzstd + _zstd + compression/zstd (curl_cffi statically links its own zstd;
  # shutil/zipfile/tarfile guard zstd imports with try/except).
  rm -f "$stage"/usr/lib/libzstd.so*
  find "$py_lib_dir/lib-dynload" -maxdepth 1 -type f -name '_zstd*.so' -delete 2>/dev/null || true
  rm -rf "$py_lib_dir/compression/zstd"

  # C2: remove unused interactive/dev/mail stdlib modules and broken _dbm extension
  # (_dbm needs libgdbm_compat.so which is already deleted).
  rm -f \
    "$py_lib_dir/pdb.py" \
    "$py_lib_dir/bdb.py" \
    "$py_lib_dir/doctest.py" \
    "$py_lib_dir/mailbox.py" \
    "$py_lib_dir/smtplib.py" \
    "$py_lib_dir/imaplib.py" \
    "$py_lib_dir/poplib.py" \
    "$py_lib_dir/dbm/ndbm.py" \
    "$py_lib_dir/dbm/gnu.py"
  rm -rf \
    "$py_lib_dir/venv" \
    "$py_lib_dir/ensurepip" \
    "$py_lib_dir/curses"
  find "$py_lib_dir/lib-dynload" -maxdepth 1 -type f -name '_dbm*.so' -delete 2>/dev/null || true

  # C3: remove dead leftovers, dangling symlinks, and unused unversioned linker symlinks.
  rm -f \
    "$stage/usr/lib/libcrypt.so" \
    "$stage/usr/lib/engines-3/capi.so" \
    "$stage/usr/lib/pkgIndex.tcl"
  find "$py_lib_dir/lib-dynload" -maxdepth 1 -type f \
    \( -name 'xxlimited*.so' -o -name 'xxsubtype*.so' \) -delete 2>/dev/null || true
  find "$stage/usr/lib" -xtype l -delete 2>/dev/null || true

  # Remove unversioned lib*.so linker symlinks pointing to versioned lib*.so.N,
  # except libz.so (needed by FFmpeg) and libsqlite3.so (needed by _sqlite3/aria2c),
  # after verifying via readelf -d that no ELF in the staged payload lists them in NEEDED.
  local all_stage_needed sym sym_name sym_target
  all_stage_needed="$(
    find "$stage" -type f -name '*.so*' -exec readelf -d {} + 2>/dev/null \
      | sed -n 's/.*(NEEDED).*Shared library: \[\(.*\)\].*/\1/p' \
      | sort -u
  )"
  while IFS= read -r -d '' sym; do
    sym_name="$(basename "$sym")"
    case "$sym_name" in
      libz.so|libsqlite3.so) continue ;;
    esac
    sym_target="$(readlink "$sym")"
    case "$sym_target" in
      lib*.so.*)
        if printf '%s\n' "$all_stage_needed" | grep -Fxq "$sym_name"; then
          warn "Keeping unversioned symlink $sym_name (referenced in NEEDED by staged payload)"
        else
          rm -f "$sym"
        fi
        ;;
    esac
  done < <(find "$stage/usr/lib" -maxdepth 1 -type l -name 'lib*.so' -print0)

  local py_out_dir="$OUT_DIR/python/$abi"
  local archive_out="$py_out_dir/libpython-${FULL_VER}-${abi}.tar.xz.so"
  local launcher_out="$py_out_dir/libpython-${FULL_VER}-${abi}.so"
  rm -rf "$py_out_dir"
  mkdir -p "$py_out_dir"

  local xz_bcj_flag
  case "$abi" in
    arm64-v8a)   xz_bcj_flag="--arm64" ;;
    armeabi-v7a) xz_bcj_flag="--armthumb" ;;
    x86_64|x86)  xz_bcj_flag="--x86" ;;
    *) die "unsupported ABI for xz BCJ filter: $abi" ;;
  esac

  log "Compressing runtime for $abi -> $archive_out (tar.xz $xz_bcj_flag -9e dict=16MiB)"
  rm -f "$archive_out"
  (cd "$stage" && tar -cf - usr | xz -c "$xz_bcj_flag" --lzma2=preset=9e,dict=16MiB > "$archive_out")

  log "Copying interpreter launcher for $abi -> $launcher_out"
  cp "$runtime_prefix/bin/python${MAJ_MIN}" "$launcher_out"

  file "$launcher_out"
  readelf -d "$launcher_out" | grep NEEDED || true
  tar -tJf "$archive_out" | tail -5

  log "$abi packaged: $archive_out + $launcher_out"
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
