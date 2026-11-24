#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ABI="${1:-}"
if [ -z "$ABI" ]; then
  ABI=arm64-v8a
  for f in ONLY_PYTHON ONLY_QUICKJS ONLY_FFMPEG ONLY_ARIA2 ONLY_LIBFFI ONLY_CFFI ONLY_CURL_IMPERSONATE ONLY_CURL_CFFI; do
    if [ "${!f:-0}" = "1" ]; then ABI=all; break; fi
  done
fi
FROM_STAGE="${2:-00}"
TO_STAGE="${3:-90}"

case "$ABI" in
  all)
    ABI_LABEL="all"
    ;;
  arm64-v8a|armeabi-v7a|x86_64)
    export ABIS="$ABI"
    ABI_LABEL="$ABI"
    ;;
  *) die "invalid ABI '$ABI' (expected arm64-v8a, armeabi-v7a, x86_64, or all)" ;;
esac

if [ "${ONLY_LIBFFI:-0}" = "1" ]; then
  if [ "${ONLY_CFFI:-0}" != "1" ]; then
    warn "ONLY_LIBFFI set: implying ONLY_CFFI=1 (stage 20 links libffi into CFFI)"
    export ONLY_CFFI=1
  fi
fi

if [ "${ONLY_CURL_IMPERSONATE:-0}" = "1" ]; then
  if [ "${ONLY_CURL_CFFI:-0}" != "1" ]; then
    warn "ONLY_CURL_IMPERSONATE set: implying ONLY_CURL_CFFI=1 (stage 40 links curl-impersonate into curl_cffi)"
    export ONLY_CURL_CFFI=1
  fi
fi

if [ "${ONLY_LIBFFI:-0}" = "1" ] || [ "${ONLY_CFFI:-0}" = "1" ] || [ "${ONLY_CURL_IMPERSONATE:-0}" = "1" ] || [ "${ONLY_CURL_CFFI:-0}" = "1" ]; then
  if [ "${ONLY_PYTHON:-0}" != "1" ]; then
    warn "ONLY_LIBFFI / ONLY_CFFI / ONLY_CURL_IMPERSONATE / ONLY_CURL_CFFI set: implying ONLY_PYTHON=1 (stage 50 packages these into libpython.tar.xz.so)"
    export ONLY_PYTHON=1
  fi
fi

if [ "${ONLY_PYTHON:-0}" = "1" ] || [ "${ONLY_QUICKJS:-0}" = "1" ] || [ "${ONLY_FFMPEG:-0}" = "1" ] || [ "${ONLY_ARIA2:-0}" = "1" ] \
   || [ "${ONLY_LIBFFI:-0}" = "1" ] || [ "${ONLY_CFFI:-0}" = "1" ] || [ "${ONLY_CURL_IMPERSONATE:-0}" = "1" ] || [ "${ONLY_CURL_CFFI:-0}" = "1" ]; then
  ONLY_MODE=1
else
  ONLY_MODE=0
fi

[[ "$FROM_STAGE" =~ ^(00|10|20|30|40|50|60|70|80|90|95)$ ]] || die "invalid FROM stage: $FROM_STAGE"
[[ "$TO_STAGE" =~ ^(00|10|20|30|40|50|60|70|80|90|95)$ ]] || die "invalid TO stage: $TO_STAGE"

if (( 10#$FROM_STAGE > 10#$TO_STAGE )); then
  die "FROM stage ($FROM_STAGE) must be <= TO stage ($TO_STAGE)"
fi

: "${WORK_ROOT:=$BASE_DIR/build}"
export WORK_ROOT
mkdir -p "$WORK_ROOT"

LOG_DIR="${DEV_LOG_DIR:-$WORK_ROOT/logs}"
mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
MAIN_LOG="$LOG_DIR/dev-${ABI_LABEL}-${FROM_STAGE}-${TO_STAGE}-${STAMP}.log"
TRACE_LOG="$LOG_DIR/dev-${ABI_LABEL}-${FROM_STAGE}-${TO_STAGE}-${STAMP}.trace.log"

exec > >(tee -a "$MAIN_LOG") 2>&1
exec 9>>"$TRACE_LOG"
export BASH_XTRACEFD=9
export PS4='+ [$(date "+%Y-%m-%d %H:%M:%S.%3N")] [${BASH_SOURCE##*/}:${LINENO}] '

CURRENT_STAGE="startup"
# shellcheck disable=SC2154
trap 'rc=$?; echo; echo "============================================================"; echo "FAILED"; echo "stage     : $CURRENT_STAGE"; echo "exit code : $rc"; echo "command   : $BASH_COMMAND"; echo "source    : ${BASH_SOURCE[0]}"; echo "line      : ${BASH_LINENO[0]}"; echo "main log  : $MAIN_LOG"; echo "trace log : $TRACE_LOG"; echo "============================================================"; exit "$rc"' ERR

STAGES=(
  00-setup-toolchains.sh
  10-build-libffi.sh
  20-build-cffi.sh
  30-build-curl-impersonate.sh
  40-build-curl-cffi.sh
  50-build-python.sh
  60-build-ffmpeg.sh
  70-build-quickjs.sh
  80-build-aria2.sh
  90-install-payloads.sh
  95-verify-payloads.sh
)

stage_num() { printf '%s' "${1%%-*}"; }

should_run() {
  local n="$1"
  (( 10#$n >= 10#$FROM_STAGE && 10#$n <= 10#$TO_STAGE )) || return 1
  if [ "$ONLY_MODE" = "1" ]; then
    case "$n" in
      00|90|95) return 0 ;;
      10) [ "${ONLY_LIBFFI:-0}" = "1" ] ;;
      20) [ "${ONLY_CFFI:-0}" = "1" ] ;;
      30) [ "${ONLY_CURL_IMPERSONATE:-0}" = "1" ] ;;
      40) [ "${ONLY_CURL_CFFI:-0}" = "1" ] ;;
      50) [ "${ONLY_PYTHON:-0}" = "1" ] ;;
      60) [ "${ONLY_FFMPEG:-0}" = "1" ] ;;
      70) [ "${ONLY_QUICKJS:-0}" = "1" ] ;;
      80) [ "${ONLY_ARIA2:-0}" = "1" ] ;;
      *) return 1 ;;
    esac
    return
  fi
  return 0
}

echo "============================================================"
echo "Library development build"
echo "============================================================"
echo "ABI                 : $ABI"
echo "FROM_STAGE          : $FROM_STAGE"
echo "TO_STAGE            : $TO_STAGE"
echo "WORK_ROOT           : $WORK_ROOT"
echo "TERMUX_PACKAGES_DIR : $TERMUX_PACKAGES_DIR"
echo "YTDLP_ANDROID_DIR   : $YTDLP_ANDROID_DIR"
echo "main log            : $MAIN_LOG"
echo "trace log           : $TRACE_LOG"
echo "started             : $(date --iso-8601=seconds)"
echo


echo "--- host/toolchain snapshot ---"
uname -a || true
printf 'python: '; python3 --version || true
printf 'git: '; git --version || true
printf 'cmake: '; cmake --version 2>/dev/null | head -1 || true
printf 'ninja: '; ninja --version 2>/dev/null || true
printf 'docker: '; docker --version 2>/dev/null || true
printf 'adb: '; adb version 2>/dev/null | head -1 || true
if [ -f "$TERMUX_PACKAGES_DIR/packages/python/build.sh" ]; then
  printf 'Termux Python: '
  python_full_version || true
fi
echo

for stage in "${STAGES[@]}"; do
  n="$(stage_num "$stage")"
  should_run "$n" || continue

  
  
  
  if [ "$n" = "95" ] && ! adb get-state >/dev/null 2>&1; then
    warn "Skipping $stage: no adb device/emulator attached"
    continue
  fi

  CURRENT_STAGE="$stage"
  echo
  echo "############################################################"
  echo "# START $stage"
  echo "############################################################"
  started="$(date +%s)"
  set -x
  "$SCRIPT_DIR/$stage"
  set +x
  ended="$(date +%s)"
  echo "# PASS $stage ($((ended-started))s)"
done

CURRENT_STAGE="final-audit"
echo
echo "--- artifacts currently present for $ABIS ---"
for a in $ABIS; do
  find "$OUT_DIR" -maxdepth 3 -type f \( -path "*/$a/*" -o -name "*-$a.so" -o -name "*-$a.zip.so" \) -print 2>/dev/null | sort || true
done

echo
echo "--- module AAR entries for $ABIS ---"
for aar in \
  "$YTDLP_ANDROID_DIR/natives/build/outputs/aar/natives-release.aar" \
  "$YTDLP_ANDROID_DIR/natives-x86_64/build/outputs/aar/natives-x86_64-release.aar" \
  "$YTDLP_ANDROID_DIR/main-lib/build/outputs/aar/main-lib-release.aar"; do
  [ -f "$aar" ] || continue
  echo "== $aar =="
  for a in $ABIS; do
    unzip -l "$aar" | grep "jni/$a/" || true
  done
done

echo
echo "============================================================"
echo "PASS"
echo "finished  : $(date --iso-8601=seconds)"
echo "main log  : $MAIN_LOG"
echo "trace log : $TRACE_LOG"
echo "============================================================"
