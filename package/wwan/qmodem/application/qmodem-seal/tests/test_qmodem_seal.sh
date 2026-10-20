#!/usr/bin/env bash
set -euo pipefail

seal_bin=${1:-qmodem-seal}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
token='Qm7vN2_xK9pR4tY8cW3d'
wrong_token='WrongToken_8cW3d9pR4tY2'

derive()
{
    printf '%s\n%s\n' "$1" "$1" | "$seal_bin" identity derive --token-stdin
}

derive "$token" > "$test_dir/id1"
derive "$token" > "$test_dir/id2"
cmp "$test_dir/id1" "$test_dir/id2"
recipient=$(sed -n 's/^recipient=//p' "$test_dir/id1")
[ -n "$recipient" ]

printf 'fixture\000binary\r\nwith-tail\r\n\r\n' > "$test_dir/input.tar.gz"
for n in 1 2; do
    "$seal_bin" seal --recipient "$recipient" --input "$test_dir/input.tar.gz" \
        --payload "$test_dir/payload$n.enc" --key "$test_dir/key$n.enc" > "$test_dir/review$n"
done
! cmp -s "$test_dir/payload1.enc" "$test_dir/payload2.enc"

wrapped_key_hex=$(xxd -p "$test_dir/key1.enc" | tr -d '\n')
jq -n --arg wrapped_key_hex "$wrapped_key_hex" \
    '{format:"qmodem-feedback-v1",wrapped_key_hex:$wrapped_key_hex}' \
    > "$test_dir/manifest.json"
# The production archive uses fixed member names.
mkdir "$test_dir/archive"
cp "$test_dir/manifest.json" "$test_dir/archive/manifest.json"
cp "$test_dir/payload1.enc" "$test_dir/archive/payload.enc"
tar -cf "$test_dir/feedback.tar" -C "$test_dir/archive" manifest.json payload.enc

review_key=$(sed -n 's/^review_key=//p' "$test_dir/review1")
recovered_review=$(printf '%s\n' "$token" | "$seal_bin" review-key --token-stdin \
    --manifest "$test_dir/manifest.json" | sed -n 's/^review_key=//p')
[ "$review_key" = "$recovered_review" ]
if printf '%s\n' "$wrong_token" | "$seal_bin" review-key --token-stdin \
    --manifest "$test_dir/manifest.json" > "$test_dir/wrong-review" 2>/dev/null; then
    echo 'wrong token unexpectedly recovered review key' >&2
    exit 1
fi
[ ! -s "$test_dir/wrong-review" ]
printf '%s\n' "$review_key" | "$seal_bin" decrypt --review-key --token-stdin \
    --input "$test_dir/feedback.tar" --output "$test_dir/review.out"
printf '%s\n' "$token" | "$seal_bin" decrypt --token-stdin \
    --input "$test_dir/feedback.tar" --output "$test_dir/token.out"
cmp "$test_dir/input.tar.gz" "$test_dir/review.out"
cmp "$test_dir/input.tar.gz" "$test_dir/token.out"

if printf '%s\n' "$wrong_token" | "$seal_bin" decrypt --token-stdin \
    --input "$test_dir/feedback.tar" --output "$test_dir/wrong.out" 2>/dev/null; then
    echo 'wrong token unexpectedly decrypted feedback' >&2
    exit 1
fi
[ ! -e "$test_dir/wrong.out" ]

cp "$test_dir/payload1.enc" "$test_dir/archive/payload.enc"
printf '\001' | dd of="$test_dir/archive/payload.enc" bs=1 seek=40 conv=notrunc status=none
tar -cf "$test_dir/tampered.tar" -C "$test_dir/archive" manifest.json payload.enc
if printf '%s\n' "$review_key" | "$seal_bin" decrypt --review-key --token-stdin \
    --input "$test_dir/tampered.tar" --output "$test_dir/tampered.out" 2>/dev/null; then
    echo 'tampered feedback unexpectedly decrypted' >&2
    exit 1
fi
[ ! -e "$test_dir/tampered.out" ]

echo 'qmodem-seal tests passed'
