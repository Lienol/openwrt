#!/usr/bin/env bash
# The same vendor command may have different bytes on different model/platform profiles.
set -euo pipefail

PACKAGE_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

write_fixture()
{
    local platform=$1 model=$2 model_dir=$3 response=$4 dir hex
    dir="$test_root/testcases/quectel/$platform/$model_dir"
    mkdir -p "$dir"
    hex=$(printf '%s' "$response" | xxd -p | tr -d '\n')
    jq -n --arg platform "$platform" --arg model "$model" --arg hex "$hex" \
        '{vendor:"quectel",platform:$platform,model:$model,command:"AT+CGSN",
          response_hex:$hex,tool:"at",rc:0}' > "$dir/AT_CGSN.json"
}

write_fixture qualcomm RM500Q-AE rm500q-ae-9f94df3c $'QUALCOMM\r\nOK\r\n'
write_fixture unisoc UDX710 udx710-861f4136 $'UNISOC\r\nOK\r\n'

output=$(QMODEM_TEST_REPO_ROOT="$test_root" "$PACKAGE_DIR/tests/test_vendor_fixtures.sh")
printf '%s\n' "$output" | grep -q 'quectel/qualcomm/rm500q-ae-9f94df3c: replay passed'
printf '%s\n' "$output" | grep -q 'quectel/unisoc/udx710-861f4136: replay passed'

echo 'fixture profile isolation tests passed'
