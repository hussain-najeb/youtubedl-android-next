#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export REQUIRE_ALL_PAYLOADS=1
unset ONLY_PYTHON ONLY_QUICKJS ONLY_FFMPEG ONLY_ARIA2 ONLY_LIBFFI ONLY_CFFI ONLY_CURL_IMPERSONATE ONLY_CURL_CFFI STRICT_PARTIAL

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
)

for stage in "${STAGES[@]}"; do
  echo
  echo "############################################################"
  echo "# $stage"
  echo "############################################################"
  "$SCRIPT_DIR/$stage"
done

echo
echo "All stages complete. Run scripts/95-verify-payloads.sh with a device"
echo "attached to run the on-device verification matrix."
