#!/usr/bin/env bash
# Replay collected AT fixtures by vendor/platform/model profile.
# Layers: 1) fixture metadata and command heads must be valid;
#         2) read-only vendor methods must run cleanly and emit valid JSON;
#         3) profile-scoped expected/<method>.json snapshots are diffed.
set -u

TESTS_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$TESTS_DIR/lib/test_env.sh"

fail=0
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

mapfile -t profile_dirs < <(
    find "$REPO_ROOT/testcases" -mindepth 4 -maxdepth 4 -type f -name '*.json' \
        -not -path '*/expected/*' -printf '%h\n' | sort -u
)

for profile_dir in "${profile_dirs[@]}"; do
    rel_profile=${profile_dir#"$REPO_ROOT/testcases/"}
    IFS=/ read -r vendor profile_platform profile_model extra <<< "$rel_profile"
    profile_label="$vendor/$profile_platform/$profile_model"
    if [ -n "${extra:-}" ]; then
        echo "FAIL: invalid testcase profile path: $rel_profile"
        fail=1
        continue
    fi

    if [ "$vendor" = "core" ]; then
        cmds_file="$QMODEM_HOME/cmds/generic.sh"
        vendor_file="$QMODEM_HOME/generic.sh"
    else
        cmds_file="$QMODEM_HOME/cmds/$vendor.sh"
        vendor_file="$QMODEM_HOME/vendor/$vendor.sh"
    fi
    if [ ! -f "$cmds_file" ] || [ ! -f "$vendor_file" ]; then
        echo "WARN: $profile_label: no matching cmds/vendor file, skipping"
        continue
    fi

    first_fixture=$(find "$profile_dir" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)
    fixture_model=$(jq -r '.model // empty' "$first_fixture")
    [ -n "$fixture_model" ] || fixture_model=unknown
    fixture_vendor=$(jq -r '.vendor // empty' "$first_fixture")
    fixture_platform=$(jq -r '.platform // empty' "$first_fixture")
    fixture_modes=$(jq -r '.capabilities.modes // [] | join(" ")' "$first_fixture")
    [ -n "$fixture_modes" ] || fixture_modes=$(jq -r --arg model "$fixture_model" '
        [.modem_support[] | .[$model]? | .modes[]?] | join(" ")
    ' "$QMODEM_HOME/modem_support.json")
    fixture_bands=$(jq -r --arg model "$fixture_model" '
        [.modem_support[] | .[$model]?] | first // {} |
        [.wcdma_band // "", .lte_band // "", .nsa_band // "", .sa_band // ""] | @tsv
    ' "$QMODEM_HOME/modem_support.json")
    IFS=$'\t' read -r fixture_wcdma_band fixture_lte_band fixture_nsa_band fixture_sa_band <<< "$fixture_bands"
    profile_vendor_value=$fixture_vendor
    profile_platform_value=$fixture_platform
    profile_at_port=$(jq -r '
        [.modem_info[]? | select(.key == "at_port") | .value][0] // empty
    ' "$profile_dir/expected/base_info.json" 2>/dev/null)
    if [ "$(profile_segment "$fixture_vendor" core)" != "$vendor" ] || \
       [ "$(profile_segment "$fixture_platform" unknown)" != "$profile_platform" ] || \
       [ "$(model_segment "$fixture_model")" != "$profile_model" ]; then
        echo "FAIL: $profile_label: profile path does not match fixture metadata"
        fail=1
        continue
    fi

    LOOKUP=$(mktemp -d)
    CMDS_LIST="$LOOKUP/commands.txt"
    : > "$CMDS_LIST"
    for f in "$profile_dir"/*.json; do
        [ -f "$f" ] || continue
        fixture_vendor=$(jq -r '.vendor // empty' "$f")
        fixture_platform=$(jq -r '.platform // empty' "$f")
        current_model=$(jq -r '.model // empty' "$f")
        if [ "$fixture_vendor" != "$profile_vendor_value" ] || \
           [ "$fixture_platform" != "$profile_platform_value" ] || \
           [ "$current_model" != "$fixture_model" ]; then
            echo "FAIL: $profile_label: metadata/path mismatch in $(basename "$f")"
            fail=1
            continue
        fi
        cmd=$(jq -r '.command' "$f")
        h=$(printf '%s' "$cmd" | md5sum | cut -c1-8)
        if [ -e "$LOOKUP/$h.response" ]; then
            echo "FAIL: $profile_label: duplicate command fixture: $cmd"
            fail=1
            continue
        fi
        response_hex=$(jq -r '.response_hex // empty' "$f")
        if [ -n "$response_hex" ]; then
            fixture_hex_decode "$response_hex" > "$LOOKUP/$h.response"
        else
            jq -j '.response' "$f" > "$LOOKUP/$h.response"
        fi
        jq -r '.rc // 0' "$f" > "$LOOKUP/$h.rc"
        printf '%s\n' "$cmd" >> "$CMDS_LIST"
    done

    while read -r cmd; do
        [ -n "$cmd" ] || continue
        head=${cmd%%[=?]*}
        esc_head=$(printf '%s' "$head" | sed 's/\([$"]\)/\\\1/g')
        if ! grep -qF "$head" "$cmds_file" "$QMODEM_HOME/cmds/generic.sh" 2>/dev/null \
           && ! grep -qF "$esc_head" "$cmds_file" "$QMODEM_HOME/cmds/generic.sh" 2>/dev/null; then
            echo "FAIL: $profile_label: command head '$head' not found in cmds layer"
            fail=1
        fi
    done < "$CMDS_LIST"

    (
    . "$TESTS_DIR/lib/test_env.sh"
    if [ -n "$profile_at_port" ]; then
        at_port=$profile_at_port
        export at_port
    fi
    vendor="$vendor"
    platform="$profile_platform"
    QMODEM_TESTCASE_MODEL="$fixture_model"
    QMODEM_TESTCASE_MODES="$fixture_modes"
    QMODEM_TESTCASE_WCDMA_BAND="$fixture_wcdma_band"
    QMODEM_TESTCASE_LTE_BAND="$fixture_lte_band"
    QMODEM_TESTCASE_NSA_BAND="$fixture_nsa_band"
    QMODEM_TESTCASE_SA_BAND="$fixture_sa_band"
    export vendor platform QMODEM_TESTCASE_MODEL QMODEM_TESTCASE_MODES
    export QMODEM_TESTCASE_WCDMA_BAND QMODEM_TESTCASE_LTE_BAND
    export QMODEM_TESTCASE_NSA_BAND QMODEM_TESTCASE_SA_BAND
    . "$QMODEM_JSHN"
    . "$vendor_file"
    FIXTURE_LOOKUP="$LOOKUP"
    export FIXTURE_LOOKUP
    . "$TESTS_DIR/lib/at_fixture.sh"

    for fixture in "$profile_dir"/*.json; do
        [ -f "$fixture" ] || continue
        fixture_cmd=$(jq -r '.command' "$fixture")
        fixture_tool=$(jq -r '.tool // "at"' "$fixture")
        fixture_rc=$(jq -r '.rc // 0' "$fixture")
        expected_file="$LOOKUP/expected.response"
        replayed_file="$LOOKUP/replayed.response"
        fixture_hex=$(jq -r '.response_hex // empty' "$fixture")
        if [ -n "$fixture_hex" ]; then
            fixture_hex_decode "$fixture_hex" > "$expected_file"
        else
            jq -j '.response' "$fixture" > "$expected_file"
        fi
        "$fixture_tool" "$at_port" "$fixture_cmd" > "$replayed_file"
        replayed_rc=$?
        if [ "$replayed_rc" -ne "$fixture_rc" ] || ! cmp "$expected_file" "$replayed_file"; then
            echo "FAIL: $profile_label: fixture replay mismatch: $(basename "$fixture")"
            exit 1
        fi
    done

    for exp in "$profile_dir"/expected/*.json; do
        [ -f "$exp" ] || continue
        method=$(basename "$exp" .json)
        case "$method" in
            base_info|cell_info|get_*) ;;
            *) echo "WARN: $profile_label: refusing non-read-only snapshot method: $method"; continue ;;
        esac
        if ! command -v "$method" >/dev/null; then
            echo "WARN: $profile_label: $method not defined, skipping snapshot"
            continue
        fi
        json_init
        json_add_object result
        json_close_object
        case "$method" in
            base_info|cell_info)
                json_add_array modem_info
                "$method"
                json_close_array
                ;;
            *) "$method" ;;
        esac
        out=$(json_dump)
        rc=$?
        if [ "$rc" -ne 0 ] || ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
            echo "FAIL: $profile_label: $method failed (rc=$rc) or emitted invalid JSON"
            exit 1
        fi
        if ! diff <(jq -S . "$exp") <(printf '%s' "$out" | jq -S .) >/dev/null; then
            echo "FAIL: $profile_label: $method differs from expected/$method.json:"
            diff <(jq -S . "$exp") <(printf '%s' "$out" | jq -S .) | head -20
            exit 1
        fi
        echo "OK: $profile_label: $method matches golden snapshot"
    done

    echo "OK: $profile_label: replay passed"
    ) || fail=1

    if [ -f "$LOOKUP/misses.log" ]; then
        echo "INFO: $profile_label: commands used but without fixtures:"
        sort -u "$LOOKUP/misses.log" | sed 's/^/  /' | head -10
    fi
    rm -rf "$LOOKUP"
done

echo '--- fixture coverage (warn only) ---'
for cmds_file in "$QMODEM_HOME"/cmds/*.sh; do
    v=$(basename "$cmds_file" .sh)
    missing_file=$(mktemp)
    sed -n 's/.*at "$1" ["'\''"]\([^"'\''"]*\).*/\1/p' "$cmds_file" | while read -r lit; do
        lit=$(printf '%s' "$lit" | sed 's/^\${2}//; s/^$2//')
        head=$(printf '%s' "$lit" | sed 's/[^A-Za-z0-9+!^#&*$-].*$//')
        [ -n "$head" ] || continue
        found=0
        case "$v" in
            generic|modem_dial|modem_util) fixture_roots=("$REPO_ROOT/testcases") ;;
            *) fixture_roots=("$REPO_ROOT/testcases/$v" "$REPO_ROOT/testcases/core") ;;
        esac
        for fixture_root in "${fixture_roots[@]}"; do
            [ -d "$fixture_root" ] || continue
            if find "$fixture_root" -type f -name '*.json' -not -path '*/expected/*' \
                -exec jq -r '.command' {} + 2>/dev/null | grep -qF "$head"; then
                found=1
                break
            fi
        done
        if [ "$found" -eq 0 ]; then
            printf '%s\n' "$head" >> "$missing_file"
        fi
    done
    missing=$(sort -u "$missing_file" | wc -l)
    [ "$missing" -eq 0 ] || echo "  $v: $missing command heads without fixtures"
    rm -f "$missing_file"
done

if [ "$fail" -eq 0 ]; then
    echo 'vendor fixture tests passed'
else
    echo 'vendor fixture tests FAILED' >&2
    exit 1
fi
