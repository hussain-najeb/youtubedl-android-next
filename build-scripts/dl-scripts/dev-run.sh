#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ABI="${1:-arm64-v8a}"
FROM_STAGE="${2:-00}"
TO_STAGE="${3:-90}"

case "$ABI" in
  arm64-v8a|armeabi-v7a|x86_64) ;;
  *) die "invalid ABI '$ABI' (expected arm64-v8a, armeabi-v7a, or x86_64)" ;;
esac

[[ "$FROM_STAGE" =~ ^(00|10|20|30|40|50|60|70|80|90|95)$ ]] || die "invalid FROM stage: $FROM_STAGE"
[[ "$TO_STAGE" =~ ^(00|10|20|30|40|50|60|70|80|90|95)$ ]] || die "invalid TO stage: $TO_STAGE"

if (( 10#$FROM_STAGE > 10#$TO_STAGE )); then
  die "FROM stage ($FROM_STAGE) must be <= TO stage ($TO_STAGE)"
fi

export ABIS="$ABI"

: "${WORK_ROOT:=$BASE_DIR/build}"
export WORK_ROOT
mkdir -p "$WORK_ROOT"

LOG_DIR="${DEV_LOG_DIR:-$WORK_ROOT/logs}"
mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
MAIN_LOG="$LOG_DIR/dev-${ABI}-${FROM_STAGE}-${TO_STAGE}-${STAMP}.log"
TRACE_LOG="$LOG_DIR/dev-${ABI}-${FROM_STAGE}-${TO_STAGE}-${STAMP}.trace.log"

exec > >(tee -a "$MAIN_LOG") 2>&1
exec 9>>"$TRACE_LOG"
export BASH_XTRACEFD=9
export PS4='+ [$(date "+%Y-%m-%d %H:%M:%S.%3N")] [${BASH_SOURCE##*/}:${LINENO}] '

CURRENT_STAGE="startup"
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
  (( 10#$n >= 10#$FROM_STAGE && 10#$n <= 10#$TO_STAGE ))
}

echo "============================================================"
echo "Fermux development build"
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
echo "--- artifacts currently present for $ABI ---"
find "$OUT_DIR" -maxdepth 3 -type f \( -path "*/$ABI/*" -o -name "*-$ABI.so" -o -name "*-$ABI.zip.so" \) -print 2>/dev/null | sort || true

echo
echo "--- module AAR entries for $ABI ---"
for aar in \
  "$YTDLP_ANDROID_DIR/natives/build/outputs/aar/natives-release.aar" \
  "$YTDLP_ANDROID_DIR/main-lib/build/outputs/aar/main-lib-release.aar"; do
  [ -f "$aar" ] || continue
  echo "== $aar =="
  unzip -l "$aar" | grep "jni/$ABI/" || true
done

echo
echo "============================================================"
echo "PASS"
echo "finished  : $(date --iso-8601=seconds)"
echo "main log  : $MAIN_LOG"
echo "trace log : $TRACE_LOG"
echo "============================================================"
