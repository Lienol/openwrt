#!/usr/bin/env bash
# Validate AT exchanges captured before modem vendor/model discovery completes.
set -u

TESTS_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$TESTS_DIR/lib/test_env.sh"

profile_segment()
{
    local value=$1 fallback=$2 slug
    [ -n "$value" ] || value=$fallback
    slug=$(printf '%s' "$value" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9._-' '_' | cut -c1-40)
    printf '%s' "${slug:-$fallback}"
}

model_segment()
{
    local value=$1 slug
    [ -n "$value" ] || value=unknown
    slug=$(profile_segment "$value" unknown)
    if [ "$value" = unknown ]; then
        printf '%s' "$slug"
    else
        printf '%s-%s' "$slug" "$(printf '%s' "$value" | md5sum | cut -c1-8)"
    fi
}

scanner_source="$REPO_ROOT/application/modem_scan/src/modem_scand.c"
fail=0
mapfile -t fixture_files < <(
    find "$REPO_ROOT/testcases/recognition" -mindepth 4 -maxdepth 4 -type f -name '*.json' 2>/dev/null | sort
)

for fixture in "${fixture_files[@]}"; do
    rel=${fixture#"$REPO_ROOT/testcases/recognition/"}
    IFS=/ read -r vendor platform model_profile filename extra <<< "$rel"
    label="recognition/$vendor/$platform/$model_profile/$filename"
    if [ -n "${extra:-}" ]; then
        echo "FAIL: invalid recognition fixture path: $rel"
        fail=1
        continue
    fi

    expected_vendor=$(jq -r '.expected_identity.vendor // empty' "$fixture")
    expected_platform=$(jq -r '.expected_identity.platform // empty' "$fixture")
    expected_model=$(jq -r '.expected_identity.model // empty' "$fixture")
    if [ "$(jq -r '.phase // empty' "$fixture")" != recognition ] || \
       [ "$(profile_segment "$expected_vendor" unknown)" != "$vendor" ] || \
       [ "$(profile_segment "$expected_platform" unknown)" != "$platform" ] || \
       [ "$(model_segment "$expected_model")" != "$model_profile" ]; then
        echo "FAIL: $label: path does not match expected_identity"
        fail=1
        continue
    fi

    command=$(jq -r '.command // empty' "$fixture")
    response_hex=$(jq -r '.response_hex // empty' "$fixture")
    if [ -z "$command" ] || ! printf '%s' "$response_hex" | grep -Eq '^([0-9a-fA-F]{2})*$'; then
        echo "FAIL: $label: invalid command or response_hex"
        fail=1
        continue
    fi
    if ! grep -qF "\"$command\"" "$scanner_source"; then
        echo "FAIL: $label: command is not part of modem recognition: $command"
        fail=1
        continue
    fi
    echo "OK: $label"
done

if [ "$fail" -eq 0 ]; then
    echo "recognition fixture tests passed (${#fixture_files[@]} fixtures)"
else
    echo 'recognition fixture tests FAILED' >&2
    exit 1
fi
