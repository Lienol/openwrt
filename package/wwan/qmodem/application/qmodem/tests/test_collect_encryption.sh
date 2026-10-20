#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
collect_bin="$PACKAGE_DIR/files/usr/sbin/qmodem_collect"
seal_bin=${QMODEM_TEST_SEAL_BIN:-}
test_dir=$(mktemp -d)
plain_file=
forced_plain_file=
encrypted_file=
cleanup()
{
    rm -rf "$test_dir"
    [ -z "$plain_file" ] || rm -f "$plain_file"
    [ -z "$forced_plain_file" ] || rm -f "$forced_plain_file"
    [ -z "$encrypted_file" ] || rm -f "$encrypted_file"
}
trap cleanup EXIT

profile=quectel/qualcomm/rm500q-ae-9f94df3c
mkdir -p "$test_dir/fixtures/$profile"
response_hex=$(printf 'AT+CGSN\r\n861234567890123\r\nOK\r\n\r\n' | xxd -p | tr -d '\n')
jq -n --arg h "$response_hex" \
    '{vendor:"quectel",platform:"qualcomm",model:"RM500Q-AE",
      command:"AT+CGSN",response_hex:$h,tool:"at",rc:0}' \
    > "$test_dir/fixtures/$profile/cgsn.json"

plain_output=$(QMODEM_COLLECT_DIR="$test_dir/fixtures" \
    QMODEM_SEAL_BIN=/not-installed/qmodem-seal "$collect_bin" pack 2>&1)
printf '%s\n' "$plain_output" | grep -q 'UNENCRYPTED'
printf '%s\n' "$plain_output" | grep -q 'encryption: OFF'
plain_file=$(printf '%s\n' "$plain_output" | sed -n 's/.* -> //p')
tar -tzf "$plain_file" | grep -q "$profile/cgsn.json"

# Encryption tests are skipped in generic shell-only CI unless a compiled
# qmodem-seal is explicitly supplied.
if [ -z "$seal_bin" ]; then
    echo 'qmodem_collect plaintext fallback tests passed'
    exit 0
fi

token='Qm7vN2_xK9pR4tY8cW3d'
identity=$(printf '%s\n%s\n' "$token" "$token" | "$seal_bin" identity derive --token-stdin)
recipient=$(printf '%s\n' "$identity" | sed -n 's/^recipient=//p')
recipient_id=$(printf '%s\n' "$identity" | sed -n 's/^recipient_id=//p')
encrypted_output=$(QMODEM_COLLECT_DIR="$test_dir/fixtures" QMODEM_SEAL_BIN="$seal_bin" \
    QMODEM_SEAL_RECIPIENT="$recipient" QMODEM_SEAL_RECIPIENT_ID="$recipient_id" \
    "$collect_bin" pack)
printf '%s\n' "$encrypted_output" | grep -q 'encryption: ON'
encrypted_file=$(printf '%s\n' "$encrypted_output" | sed -n 's/.* -> //p')
review_key=$(printf '%s\n' "$encrypted_output" | sed -n 's/^review password\/key (keep private): //p')
[ -n "$review_key" ]
tar -tf "$encrypted_file" | grep -q '^manifest.json$'
if tar -tf "$encrypted_file" | grep -q '^key.enc$'; then
    echo 'wrapped key must be carried by manifest only' >&2
    exit 1
fi
tar -xOf "$encrypted_file" manifest.json | jq -e \
    --arg id "$recipient_id" \
    '.encrypted == true and .sanitized == true and .recipient_id == $id and
     (.wrapped_key_hex | type == "string" and length > 0)' >/dev/null
tar -xOf "$encrypted_file" manifest.json > "$test_dir/manifest.json"
owner_review=$(printf '%s\n' "$token" | "$seal_bin" review-key --token-stdin \
    --manifest "$test_dir/manifest.json" | sed -n 's/^review_key=//p')
[ "$review_key" = "$owner_review" ]
printf '%s\n' "$review_key" | "$seal_bin" decrypt --review-key --token-stdin \
    --input "$encrypted_file" --output "$test_dir/review.tar.gz"
tar -xOzf "$test_dir/review.tar.gz" "./$profile/cgsn.json" \
    | jq -r '.response_hex' | xxd -r -p \
    | cmp - <(printf 'AT+CGSN\r\n860000000000023\r\nOK\r\n\r\n')

forced_output=$(QMODEM_COLLECT_DIR="$test_dir/fixtures" QMODEM_SEAL_BIN="$seal_bin" \
    "$collect_bin" pack --unencrypted 2>&1)
printf '%s\n' "$forced_output" | grep -q 'encryption: OFF'
forced_plain_file=$(printf '%s\n' "$forced_output" | sed -n 's/.* -> //p')

echo 'qmodem_collect encryption tests passed'
