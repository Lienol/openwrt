#!/bin/sh
# Copyright (C) 2026 QModem contributors
_Vendor="openluat"
_Author="QModem contributors"
_Maintainer="QModem contributors"
source "${QMODEM_HOME:-/usr/share/qmodem}/generic.sh"
source "${QMODEM_HOME:-/usr/share/qmodem}/cmds/openluat.sh"

debug_subject="openluat_ctrl"


# Read only the value belonging to an exact AT response prefix. This avoids
# treating unsolicited reports (for example +CESQ) or diagnostic output as the
# response to +CGMM/+CGMI/+CGMR.
openluat_at_prefixed_value()
{
  local prefix="$1"
  awk -v prefix="$prefix" '
    function clean(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value ~ /^".*"$/) {
        sub(/^"/, "", value)
        sub(/"$/, "", value)
      }
      return value
    }
    {
      line=$0
      sub(/\r$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      if (index(line, prefix) == 1) {
        value=clean(substr(line, length(prefix) + 1))
        if (value != "" && value !~ /^\+/) {
          print value
          exit
        }
        waiting=1
        next
      }
      if (waiting) {
        value=clean(line)
        if (value == "")
          next
        if (value == "OK" || value == "ERROR" || value ~ /^\+/)
          exit
        print value
        exit
      }
    }
  '
}

# Print the primary and secondary DNS addresses (one per line) for a requested
# +CGCONTRDP context. Air724 can put the CSV data on the next line after the
# prefix, so both documented response forms are accepted.
openluat_parse_cgcontrdp_dns()
{
  local wanted_cid="$1"
  awk -v wanted_cid="$wanted_cid" '
    function clean(value) {
      gsub(/^[[:space:]\"]+|[[:space:]\"]+$/, "", value)
      return value
    }
    function parse(line, fields, count) {
      count=split(line, fields, ",")
      if (count < 8 || clean(fields[1]) != wanted_cid)
        return 0
      print clean(fields[7])
      print clean(fields[8])
      return 1
    }
    {
      line=$0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*\+CGCONTRDP:/) {
        sub(/^[[:space:]]*\+CGCONTRDP:[[:space:]]*/, "", line)
        if (line == "") {
          waiting=1
          next
        }
        if (parse(line))
          exit
        next
      }
      if (waiting) {
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line == "")
          next
        waiting=0
        if (line == "OK" || line == "ERROR" || line ~ /^\+/)
          next
        if (parse(line))
          exit
      }
    }
  '
}

openluat_is_ipv4()
{
  printf '%s\n' "$1" | awk -F. '
    BEGIN { valid=1 }
    NF != 4 { valid=0; next }
    {
      for (i=1; i<=4; i++) {
        if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) {
          valid=0
          break
        }
      }
    }
    END { exit valid ? 0 : 1 }
  '
}

vendor_get_disabled_features()
{
    json_add_string "" "IMEI"
}

openluat_query_prefixed()
{
    local command="$1"
    local prefix="$2"
    local response

    response=$(cmd_openluat_identity_query "$at_port" "$command")
    printf '%s\n' "$response" | openluat_at_prefixed_value "$prefix"
}

openluat_first_number()
{
    printf '%s\n' "$1" | grep -o '[0-9]\{15,20\}' | head -n1
}

openluat_parse_cbc_voltage()
{
    printf '%s\n' "$1" | awk '
        /^[[:space:]]*[+]CBC[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[+]CBC[[:space:]]*:[[:space:]]*/, "", line)
            field_count = split(line, fields, ",")
            if (field_count != 3)
                exit

            voltage = fields[3]
            gsub(/[[:space:]\r]/, "", voltage)
            numeric_voltage = voltage + 0
            if (voltage ~ /^[0-9]+$/ && numeric_voltage > 0 && numeric_voltage <= 10000)
                print numeric_voltage
            exit
        }
    '
}

openluat_cesq_field()
{
    local response="$1"
    local field_index="$2"

    printf '%s\n' "$response" | awk -v field_index="$field_index" '
        /^[[:space:]]*[+]CESQ[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[+]CESQ[[:space:]]*:[[:space:]]*/, "", line)
            field_count = split(line, fields, ",")
            if (field_count < 6 || field_index > field_count)
                exit

            value = fields[field_index]
            gsub(/[[:space:]]/, "", value)
            if (value ~ /^[0-9]+$/)
                print value
            exit
        }
    '
}

openluat_lte_rsrp_value()
{
    local raw="$1"

    case "$raw" in
        ''|*[!0-9]*) return ;;
    esac
    [ "$raw" -le 97 ] || return

    printf '%s\n' "$((raw - 141))"
}

openluat_lte_rsrq_value()
{
    local raw="$1"

    case "$raw" in
        ''|*[!0-9]*) return ;;
    esac
    [ "$raw" -le 34 ] || return

    awk -v raw="$raw" 'BEGIN {
        value = raw * 0.5 - 20
        if (value == int(value))
            printf "%.0f\n", value
        else
            printf "%.1f\n", value
    }'
}

# +CESQ reports quantized LTE values. Use each finite bucket's lower bound;
# values 0 and the top bucket are represented by their nearest finite bound.
openluat_cesq_rsrp()
{
    openluat_lte_rsrp_value "$(openluat_cesq_field "$1" 6)"
}

openluat_cesq_rsrq()
{
    openluat_lte_rsrq_value "$(openluat_cesq_field "$1" 5)"
}

openluat_ctec_mode()
{
    printf '%s\n' "$1" | awk '
        /^[[:space:]]*[+]CTEC[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[+]CTEC[[:space:]]*:[[:space:]]*/, "", line)
            sub(/\r$/, "", line)
            field_count = split(line, fields, ",")
            for (i = 1; i <= field_count; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[i])
            }

            value = fields[2]
            if (value !~ /^(0|2|4)$/)
                value = fields[1]
            if (value ~ /^(0|2|4)$/)
                print value
            exit
        }
    '
}

openluat_band_values()
{
    printf '%s\n' "$1" | awk '
        /^[[:space:]]*[*]BAND[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[*]BAND[[:space:]]*:[[:space:]]*/, "", line)
            sub(/\r$/, "", line)
            field_count = split(line, fields, ",")
            if (field_count < 8)
                exit

            valid = 1
            for (i = 1; i <= 8; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[i])
                if (fields[i] !~ /^[0-9]+$/)
                    valid = 0
            }
            if (!valid)
                exit

            printf "%s", fields[1]
            for (i = 2; i <= 8; i++)
                printf ",%s", fields[i]
            printf "\n"
            exit
        }
    '
}

openluat_available_lte_bands()
{
    # Air724UG supports these LTE bands. Keep this exact-model list aligned
    # with modem_support.json; do not widen it to the non-existent air724u ID.
    printf '%s\n' '1,3,5,8,34,38,39,40,41'
}

openluat_normalize_lte_bands()
{
    local compact token seen band output

    compact=$(printf '%s' "$1" | tr -d '[:space:]')
    if [ -z "$compact" ]; then
        printf '\n'
        return 0
    fi
    printf '%s\n' "$compact" | grep -Eq '^[0-9]+(,[0-9]+)*$' || return 1

    seen=","
    for token in $(printf '%s' "$compact" | tr ',' ' '); do
        case "$token" in
            1|3|5|8|34|38|39|40|41) ;;
            *) return 1 ;;
        esac
        case "$seen" in
            *",$token,"*) ;;
            *) seen="${seen}${token}," ;;
        esac
    done

    output=""
    for band in 1 3 5 8 34 38 39 40 41; do
        case "$seen" in
            *",$band,"*)
                if [ -n "$output" ]; then
                    output="$output,$band"
                else
                    output="$band"
                fi
                ;;
        esac
    done
    printf '%s\n' "$output"
}

openluat_lte_masks_from_bands()
{
    local bands band lte_high=0 lte_low=0

    bands=$(openluat_normalize_lte_bands "$1") || return 1
    for band in $(printf '%s' "$bands" | tr ',' ' '); do
        case "$band" in
            1)  lte_low=$((lte_low | 1)) ;;
            3)  lte_low=$((lte_low | 4)) ;;
            5)  lte_low=$((lte_low | 16)) ;;
            8)  lte_low=$((lte_low | 128)) ;;
            34) lte_high=$((lte_high | 2)) ;;
            38) lte_high=$((lte_high | 32)) ;;
            39) lte_high=$((lte_high | 64)) ;;
            40) lte_high=$((lte_high | 128)) ;;
            41) lte_high=$((lte_high | 256)) ;;
        esac
    done
    printf '%s,%s\n' "$lte_high" "$lte_low"
}

openluat_lte_bands_from_masks()
{
    local lte_high="$1"
    local lte_low="$2"
    local available band mask value output=""

    case "$lte_high,$lte_low" in
        *[!0-9,]*) return 1 ;;
    esac
    lte_high=$(printf '%s' "$lte_high" | sed 's/^0*//')
    lte_low=$(printf '%s' "$lte_low" | sed 's/^0*//')
    [ -n "$lte_high" ] || lte_high=0
    [ -n "$lte_low" ] || lte_low=0
    available=$(openluat_normalize_lte_bands "$3") || return 1

    for band in $(printf '%s' "$available" | tr ',' ' '); do
        case "$band" in
            1)  value=$lte_low;  mask=1 ;;
            3)  value=$lte_low;  mask=4 ;;
            5)  value=$lte_low;  mask=16 ;;
            8)  value=$lte_low;  mask=128 ;;
            34) value=$lte_high; mask=2 ;;
            38) value=$lte_high; mask=32 ;;
            39) value=$lte_high; mask=64 ;;
            40) value=$lte_high; mask=128 ;;
            41) value=$lte_high; mask=256 ;;
        esac
        if [ $((value & mask)) -ne 0 ]; then
            if [ -n "$output" ]; then
                output="$output,$band"
            else
                output="$band"
            fi
        fi
    done
    printf '%s\n' "$output"
}

openluat_parse_cced_neighbors()
{
    printf '%s\n' "$1" | awk '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]\r]+$/, "", value)
            return value
        }
        /^[[:space:]]*[+]CCED:LTE neighbor cell[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[+]CCED:LTE neighbor cell[[:space:]]*:[[:space:]]*/, "", line)
            field_count = split(line, fields, ",")
            if (field_count != 9)
                next
            printf "LTE"
            for (i = 1; i <= 9; i++)
                printf "\t%s", trim(fields[i])
            printf "\n"
            next
        }
        /^[[:space:]]*[+]CCED:GSM neighbor cell info[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[+]CCED:GSM neighbor cell info[[:space:]]*:[[:space:]]*/, "", line)
            field_count = split(line, fields, ",")
            if (field_count != 6)
                next
            printf "GSM"
            for (i = 1; i <= 6; i++)
                printf "\t%s", trim(fields[i])
            printf "\n"
        }
    '
}

openluat_parse_cced_serving()
{
    printf '%s\n' "$1" | awk '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]\r]+$/, "", value)
            return value
        }
        /^[[:space:]]*[+]CCED:LTE current cell[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[+]CCED:LTE current cell[[:space:]]*:[[:space:]]*/, "", line)
            field_count = split(line, fields, ",")
            if (field_count != 13)
                next
            printf "LTE"
            for (i = 1; i <= 13; i++)
                printf "|%s", trim(fields[i])
            printf "\n"
            exit
        }
        /^[[:space:]]*[+]CCED:GSM current cell info[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[+]CCED:GSM current cell info[[:space:]]*:[[:space:]]*/, "", line)
            field_count = split(line, fields, ",")
            if (field_count != 8)
                next
            printf "GSM"
            for (i = 1; i <= 8; i++)
                printf "|%s", trim(fields[i])
            printf "\n"
            exit
        }
    '
}

# AT+EEMGINFO? has two documented LTE service layouts. The first fourteen
# fields are shared. Air720S moves RSSI/CQI/TX power/rank deeper into its
# extended layout, so select them by the complete field count rather than by
# matching any unsolicited engineering line.
openluat_parse_eem_lte_service()
{
    printf '%s\n' "$1" | awk '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]\r]+$/, "", value)
            return value
        }
        /^[[:space:]]*[+]EEMLTESVC[[:space:]]*:/ {
            line = $0
            sub(/^[[:space:]]*[+]EEMLTESVC[[:space:]]*:[[:space:]]*/, "", line)
            field_count = split(line, fields, ",")
            if (field_count < 22)
                next
            for (i = 1; i <= field_count; i++)
                fields[i] = trim(fields[i])

            layout = "Air720"
            rssi = fields[19]
            cqi = fields[20]
            tx_power = fields[21]
            rank_index = fields[22]
            if (field_count >= 50) {
                layout = "Air720S"
                rssi = fields[32]
                cqi = fields[33]
                rank_index = fields[46]
                tx_power = fields[50]
            }

            printf "LTE|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", \
                fields[1], fields[3], fields[4], fields[5], fields[6], fields[7], \
                fields[8], fields[9], fields[10], fields[11], fields[12], fields[13], \
                fields[14], rssi, cqi, tx_power, rank_index, layout
            exit
        }
    '
}

openluat_lte_duplex_mode()
{
    local band

    band=$(printf '%s' "$1" | tr -d '[:space:]' | sed 's/^LTE//; s/^[Bb]//')
    case "$band" in
        1|3|5|8) printf '%s\n' "FDD" ;;
        34|38|39|40|41) printf '%s\n' "TDD" ;;
    esac
}

openluat_lte_bandwidth()
{
    local raw

    raw=$(printf '%s' "$1" | tr -d '[:space:]')
    case "$raw" in
        n6|6)     printf '%s\n' "1.4 MHz (n6)" ;;
        n15|15)   printf '%s\n' "3 MHz (n15)" ;;
        n25|25)   printf '%s\n' "5 MHz (n25)" ;;
        n50|50)   printf '%s\n' "10 MHz (n50)" ;;
        n75|75)   printf '%s\n' "15 MHz (n75)" ;;
        n100|100) printf '%s\n' "20 MHz (n100)" ;;
        '') ;;
        *) printf '%s\n' "$raw" ;;
    esac
}

openluat_number_in_range()
{
    awk -v value="$1" -v minimum="$2" -v maximum="$3" 'BEGIN {
        if (value ~ /^-?[0-9]+([.][0-9]+)?$/ && value >= minimum && value <= maximum)
            print value
    }'
}

openluat_normalize_rsrp()
{
    case "$1" in
        -*) openluat_number_in_range "$1" -141 -44 ;;
        *) openluat_lte_rsrp_value "$1" ;;
    esac
}

openluat_normalize_rsrq()
{
    case "$1" in
        -*) openluat_number_in_range "$1" -20 -3 ;;
        *) openluat_lte_rsrq_value "$1" ;;
    esac
}

openluat_load_serving_cell()
{
    local response options="-t 10"

    [ "${openluat_serving_cell_loaded:-0}" = "1" ] && return
    response=$(cmd_openluat_cced_serving "$at_port")
    openluat_serving_cell=$(openluat_parse_cced_serving "$response")
    openluat_serving_cell_loaded=1
}

openluat_load_eem_lte_service()
{
    local enable_response response options="-t 10"

    [ "${openluat_eem_lte_loaded:-0}" = "1" ] && return
    openluat_eem_lte_loaded=1
    enable_response=$(cmd_openluat_eem_enable "$at_port")
    openluat_at_response_ok "$enable_response" || return
    response=$(cmd_openluat_eem_info "$at_port")
    openluat_eem_lte_service=$(openluat_parse_eem_lte_service "$response")
}

openluat_at_response_ok()
{
    printf '%s\n' "$1" | grep -Eq '^[[:space:]]*OK[[:space:]\r]*$'
}

get_network_prefer()
{
    local response mode network_prefer_2g=0 network_prefer_4g=0
    local options="-t 10"

    response=$(cmd_openluat_ctec_query "$at_port")
    mode=$(openluat_ctec_mode "$response")
    case "$mode" in
        0) network_prefer_2g=1; network_prefer_4g=1 ;;
        2) network_prefer_2g=1 ;;
        4) network_prefer_4g=1 ;;
    esac

    json_add_object "network_prefer"
    json_add_string "2G" "$network_prefer_2g"
    json_add_string "4G" "$network_prefer_4g"
    json_close_object
}

set_network_prefer()
{
    local config="$1"
    local normalized mode command response status
    local options="-t 10"

    normalized=$(printf '%s' "$config" | jq -er '
        if type == "array" then sort | unique | join(",")
        else error("network preference must be an array") end
    ' 2>/dev/null)
    case "$normalized" in
        2G) mode=2 ;;
        4G) mode=4 ;;
        2G,4G) mode=0 ;;
        *)
            json_select "result"
            json_add_string "status" "error"
            json_add_string "set_network_prefer" "Air724UG supports only 2G, 4G, or automatic 2G+4G selection"
            json_close_object
            return 1
            ;;
    esac

    command="AT+CTEC=$mode,$mode"
    response=$(cmd_openluat_ctec_set "$at_port" "$mode")
    if openluat_at_response_ok "$response"; then
        status="ok"
    else
        status="error"
    fi
    json_select "result"
    json_add_string "status" "$status"
    json_add_string "set_network_prefer" "$response"
    json_add_string "command" "$command"
    json_close_object
    [ "$status" = "ok" ]
}

get_lockband()
{
    local response band_values available selected mode lte_high lte_low band
    local options="-t 10"

    response=$(cmd_openluat_band_query "$at_port")
    band_values=$(openluat_band_values "$response")
    available=$(openluat_available_lte_bands)
    selected=""
    if [ -n "$band_values" ]; then
        local old_ifs="$IFS"
        IFS=,
        set -- $band_values
        IFS="$old_ifs"
        mode=$1
        lte_high=$4
        lte_low=$5
        # In dual/triple modes the manual says band masks are ignored.
        if [ "$mode" = "5" ]; then
            selected=$(openluat_lte_bands_from_masks "$lte_high" "$lte_low" "$available")
        fi
    fi

    json_add_object "lockband"
    json_add_object "LTE"
    json_add_array "available_band"
    for band in $(printf '%s' "$available" | tr ',' ' '); do
        add_avalible_band_entry "$band" "LTE_B$band"
    done
    json_close_array
    json_add_array "lock_band"
    for band in $(printf '%s' "$selected" | tr ',' ' '); do
        [ -n "$band" ] && json_add_string "" "$band"
    done
    json_close_array
    json_close_object
    json_close_object
}

set_lockband()
{
    local config="$1"
    local band_class lock_band normalized available band
    local response band_values old_ifs current_mode gsm_band umts_band
    local roaming_config srv_domain priority
    local masks lte_high lte_low command result status
    local options="-t 10"

    band_class=$(printf '%s' "$config" | jq -er '
        .band_class | if type == "string" then . else error("invalid band class") end
    ' 2>/dev/null)
    lock_band=$(printf '%s' "$config" | jq -er '
        (.lock_band // "") | if type == "string" then . else error("invalid band list") end
    ' 2>/dev/null)
    if [ "$band_class" != "LTE" ]; then
        json_select "result"
        json_add_string "status" "error"
        json_add_string "set_lockband" "Air724UG supports LTE band selection only"
        json_close_object
        return 1
    fi

    normalized=$(openluat_normalize_lte_bands "$lock_band") || {
        json_select "result"
        json_add_string "status" "error"
        json_add_string "set_lockband" "Invalid or unsupported Air724UG LTE band"
        json_close_object
        return 1
    }
    available=$(openluat_available_lte_bands)
    for band in $(printf '%s' "$normalized" | tr ',' ' '); do
        case ",$available," in
            *",$band,"*) ;;
            *)
                json_select "result"
                json_add_string "status" "error"
                json_add_string "set_lockband" "LTE band $band is not available on Air724UG"
                json_close_object
                return 1
                ;;
        esac
    done

    response=$(cmd_openluat_band_query "$at_port")
    band_values=$(openluat_band_values "$response")
    if [ -z "$band_values" ]; then
        json_select "result"
        json_add_string "status" "error"
        json_add_string "set_lockband" "Unable to read the current AT*BAND configuration"
        json_close_object
        return 1
    fi

    old_ifs="$IFS"
    IFS=,
    set -- $band_values
    IFS="$old_ifs"
    current_mode=$1
    gsm_band=$2
    umts_band=$3
    roaming_config=$6
    srv_domain=$7
    priority=$8
    case "$current_mode" in
        0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15) ;;
        *)
            json_select "result"
            json_add_string "status" "error"
            json_add_string "set_lockband" "Invalid current AT*BAND mode"
            json_close_object
            return 1
            ;;
    esac

    if [ -z "$normalized" ] && [ "$current_mode" != "5" ]; then
        # In an automatic/dual mode there is no active LTE band lock; sending
        # the same mode resets its ignored band masks to the modem defaults.
        command="AT*BAND=$current_mode"
    else
        [ -n "$normalized" ] || normalized="$available"
        masks=$(openluat_lte_masks_from_bands "$normalized") || return 1
        lte_high=${masks%,*}
        lte_low=${masks#*,}
        command="AT*BAND=5,$gsm_band,$umts_band,$lte_high,$lte_low,$roaming_config,$srv_domain,$priority"
    fi

    result=$(cmd_openluat_band_set "$at_port" "${command#AT*BAND=}")
    if openluat_at_response_ok "$result"; then
        status="ok"
    else
        status="error"
    fi
    json_select "result"
    json_add_string "status" "$status"
    json_add_string "set_lockband" "$result"
    json_add_string "command" "$command"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$normalized"
    json_close_object
    [ "$status" = "ok" ]
}

get_neighborcell()
{
    local response neighbors tab rat
    local mcc mnc arfcn cellid rsrp_raw rsrq_raw tac srxlev pci rsrp rsrq
    local lac bsic rxlev
    local options="-t 10"

    response=$(cmd_openluat_cced_neighbors "$at_port")
    neighbors=$(openluat_parse_cced_neighbors "$response")
    tab=$(printf '\t')

    json_add_object "neighborcell"
    json_add_array "NR"
    json_close_array
    json_add_array "LTE"
    json_close_array
    json_add_array "GSM"
    json_close_array

    if [ -n "$neighbors" ]; then
        while IFS="$tab" read -r rat mcc mnc arfcn cellid rsrp_raw rsrq_raw tac srxlev pci; do
            case "$rat" in
                LTE)
                    rsrp=$(openluat_lte_rsrp_value "$rsrp_raw")
                    rsrq=$(openluat_lte_rsrq_value "$rsrq_raw")
                    json_select "LTE"
                    json_add_object ""
                    json_add_string "mcc" "$mcc"
                    json_add_string "mnc" "$mnc"
                    json_add_string "arfcn" "$arfcn"
                    json_add_string "cellid" "$cellid"
                    json_add_string "pci" "$pci"
                    json_add_string "tac" "$tac"
                    json_add_string "rsrp" "$rsrp"
                    json_add_string "rsrq" "$rsrq"
                    json_add_string "rsrp_raw" "$rsrp_raw"
                    json_add_string "rsrq_raw" "$rsrq_raw"
                    json_add_string "srxlev" "$srxlev"
                    json_close_object
                    json_select ".."
                    ;;
                GSM)
                    # Re-map the six GSM fields read into the shared variables.
                    lac=$arfcn
                    bsic=$rsrp_raw
                    rxlev=$rsrq_raw
                    json_select "GSM"
                    json_add_object ""
                    json_add_string "mcc" "$mcc"
                    json_add_string "mnc" "$mnc"
                    json_add_string "lac" "$lac"
                    json_add_string "cellid" "$cellid"
                    json_add_string "bsic" "$bsic"
                    json_add_string "rxlev" "$rxlev"
                    json_close_object
                    json_select ".."
                    ;;
            esac
        done <<EOF
$neighbors
EOF
    fi

    json_add_object "lockcell_status"
    json_add_string "Status" "scan-only"
    json_add_string "Cell lock" "AT*CELL is not supported on Air724UG"
    json_close_object
    json_close_object
}

set_neighborcell()
{
    json_select "result"
    json_add_string "status" "unsupported"
    json_add_string "setlockcell" "AT*CELL frequency/cell locking is not supported on Air724UG"
    json_close_object
}

get_imei()
{
    local response imei

    response=$(cmd_openluat_cgsn "$at_port")
    imei=$(openluat_first_number "$response" | cut -c1-15)
    json_add_string "imei" "$imei"
}

# Air724 USB composition: 1=RNDIS+AT+PPP+DIAG, 2=ECM+AT+PPP+DIAG.
get_mode()
{
    local response mode_num mode available_modes available_mode

    response=$(cmd_openluat_setusb_query "$at_port")
    mode_num=$(printf '%s\n' "$response" | sed -n 's/^[[:space:]]*[Mm]ode:[[:space:]]*\([12]\)[[:space:]]*$/\1/p' | head -n1)

    case "$mode_num" in
        1) mode="rndis" ;;
        2) mode="ecm" ;;
        *) mode="unknown" ;;
    esac

    available_modes=$(uci -q get "qmodem.$config_section.modes")
    json_add_object "mode"
    for available_mode in $available_modes; do
        if [ "$mode" = "$available_mode" ]; then
            json_add_string "$available_mode" "1"
        else
            json_add_string "$available_mode" "0"
        fi
    done
    json_close_object
}

set_mode()
{
    local mode_num stop_response response

    case "$1" in
        rndis) mode_num=1 ;;
        ecm) mode_num=2 ;;
        *)
            json_select "result"
            json_add_string "set_mode" "Invalid mode: $1"
            json_close_object
            return 1
            ;;
    esac

    # Stop the current packet-data call before changing USB composition.
    stop_response=$(cmd_openluat_rndiscall_stop "$at_port")
    response=$(cmd_openluat_setusb_set "$at_port" "$mode_num")
    json_select "result"
    json_add_string "set_mode" "$response"
    json_add_string "hangup" "$stop_response"
    json_close_object
}

get_voltage()
{
    local response voltage

    response=$(cmd_openluat_cbc "$at_port")
    voltage=$(openluat_parse_cbc_voltage "$response")
    [ -n "$voltage" ] && add_plain_info_entry "voltage" "$voltage mV" "Voltage"
}

base_info()
{
    local name manufacturer revision

    m_debug "OpenLuat base info"
    name=$(openluat_query_prefixed "AT+CGMM" "+CGMM:")
    manufacturer=$(openluat_query_prefixed "AT+CGMI" "+CGMI:")
    revision=$(openluat_query_prefixed "AT+CGMR" "+CGMR:")
    # Some Air724UG firmware revisions return an empty AT+CGMI response even
    # though the command manual defines the manufacturer as openluat.
    [ -n "$manufacturer" ] || manufacturer="openluat"

    class="Base Information"
    add_plain_info_entry "name" "$name" "Name"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    # AT+CBC is the documented VBAT query. Air724UG AT firmware does not
    # expose a documented internal-temperature command, so do not substitute
    # the OpenWrt host thermal zone and mislabel it as modem temperature.
    get_voltage
    get_connect_status
}

sim_info()
{
    local response sim_status_flag imei isp sim_number imsi iccid

    m_debug "OpenLuat SIM info"
    response=$(cmd_openluat_cpin_query "$at_port")
    sim_status_flag=$(printf '%s\n' "$response" | grep -E '^\+CPIN:|^\+CME ERROR:' | head -n1)
    sim_status=$(get_sim_status "$sim_status_flag")

    response=$(cmd_openluat_cgsn "$at_port")
    imei=$(openluat_first_number "$response" | cut -c1-15)

    class="SIM Information"
    add_plain_info_entry "SIM Status" "$sim_status" "SIM Status"
    add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity"
    [ "$sim_status" = "ready" ] || return

    response=$(cmd_openluat_cops_query "$at_port")
    isp=$(printf '%s\n' "$response" | awk -F'"' '/^\+COPS:/ { print $2; exit }')

    response=$(cmd_openluat_cnum "$at_port")
    sim_number=$(printf '%s\n' "$response" | awk -F'"' '/^\+CNUM:/ { if ($4 != "") print $4; else print $2; exit }')

    response=$(cmd_openluat_cimi "$at_port")
    imsi=$(printf '%s\n' "$response" | grep -o '[0-9]\{15\}' | head -n1)

    response=$(cmd_openluat_iccid "$at_port")
    iccid=$(printf '%s\n' "$response" | openluat_at_prefixed_value "+ICCID:" | grep -o '[0-9]\{18,20\}' | head -n1)
    if [ -z "$iccid" ]; then
        response=$(cmd_openluat_ccid "$at_port")
        iccid=$(printf '%s\n' "$response" | openluat_at_prefixed_value "+CCID:" | grep -o '[0-9]\{18,20\}' | head -n1)
    fi

    add_plain_info_entry "ISP" "$isp" "Internet Service Provider"
    add_plain_info_entry "SIM Number" "$sim_number" "SIM Number"
    add_plain_info_entry "IMSI" "$imsi" "International Mobile Subscriber Identity"
    add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity"
}

network_info()
{
    local response carrier rat_num network_type serving_rat serving_mcc serving_mnc
    local serving_imsi serving_roaming serving_band ignored duplex

    m_debug "OpenLuat network info"
    response=$(cmd_openluat_cops_query "$at_port")
    carrier=$(printf '%s\n' "$response" | awk -F'"' '/^\+COPS:/ { print $2; exit }')
    rat_num=$(printf '%s\n' "$response" | awk -F',' '/^\+COPS:/ { gsub(/\r/, "", $4); print $4; exit }')
    network_type=$(get_rat "$rat_num")

    openluat_load_serving_cell
    if [ -n "$openluat_serving_cell" ]; then
        IFS='|' read -r serving_rat serving_mcc serving_mnc serving_imsi \
            serving_roaming serving_band ignored <<EOF
$openluat_serving_cell
EOF
        if [ "$serving_rat" = "LTE" ]; then
            duplex=$(openluat_lte_duplex_mode "$serving_band")
            [ -n "$duplex" ] && network_type="$duplex LTE"
        elif [ "$serving_rat" = "GSM" ]; then
            network_type="GSM"
        fi
    fi

    class="Network Information"
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
    add_plain_info_entry "Carrier" "$carrier" "Carrier"
}

cell_info()
{
    local serving_rat mcc mnc imsi roaming band_raw bandwidth_raw dl_earfcn
    local cell_id rsrp_raw rsrq_raw tac srxlev pci lac bsic rxlev rxlev_sub arfcn
    local response rat_num duplex band bandwidth ul_bandwidth network_mode
    local csq rssi cesq_response rsrp rsrq sinr cqi tx_power
    local eem_rat eem_mcc eem_mnc eem_tac eem_pci eem_dl_earfcn eem_ul_earfcn
    local eem_band eem_dl_bandwidth eem_cell_id eem_trans_mode eem_rsrp_raw
    local eem_rsrq_raw eem_sinr_raw eem_rssi_raw eem_cqi_raw eem_tx_power_raw
    local eem_rank_index eem_layout
    local options="-t 10"

    m_debug "OpenLuat cell info"
    openluat_load_serving_cell
    if [ -n "$openluat_serving_cell" ]; then
        case "$openluat_serving_cell" in
            LTE\|*)
                IFS='|' read -r serving_rat mcc mnc imsi roaming band_raw \
                    bandwidth_raw dl_earfcn cell_id rsrp_raw rsrq_raw tac srxlev pci <<EOF
$openluat_serving_cell
EOF
                ;;
            GSM\|*)
                IFS='|' read -r serving_rat mcc mnc lac cell_id bsic rxlev \
                    rxlev_sub arfcn <<EOF
$openluat_serving_cell
EOF
                ;;
        esac
    fi

    if [ -z "$serving_rat" ]; then
        response=$(cmd_openluat_cops_query "$at_port")
        rat_num=$(printf '%s\n' "$response" | awk -F',' '/^\+COPS:/ { gsub(/[[:space:]\r\"]/, "", $4); print $4; exit }')
        serving_rat=$(get_rat "$rat_num")
    fi

    response=$(cmd_openluat_csq "$at_port")
    csq=$(printf '%s\n' "$response" | awk -F'[:,]' '/^\+CSQ:/ { gsub(/[[:space:]\r]/, "", $2); print $2; exit }')
    case "$csq" in
        ''|*[!0-9]*) rssi="" ;;
        *)
            if [ "$csq" -le 31 ]; then
                rssi=$(get_rssi "$csq")
            else
                rssi=""
            fi
            ;;
    esac

    cesq_response=$(cmd_openluat_cesq "$at_port")
    rsrp=$(openluat_cesq_rsrp "$cesq_response")
    rsrq=$(openluat_cesq_rsrq "$cesq_response")

    class="Cell Information"
    case "$serving_rat" in
        LTE)
            openluat_load_eem_lte_service
            if [ -n "$openluat_eem_lte_service" ]; then
                IFS='|' read -r eem_rat eem_mcc eem_mnc eem_tac eem_pci \
                    eem_dl_earfcn eem_ul_earfcn eem_band eem_dl_bandwidth \
                    eem_cell_id eem_trans_mode eem_rsrp_raw eem_rsrq_raw \
                    eem_sinr_raw eem_rssi_raw eem_cqi_raw eem_tx_power_raw \
                    eem_rank_index eem_layout <<EOF
$openluat_eem_lte_service
EOF
            fi

            [ -n "$mcc" ] || mcc=$eem_mcc
            [ -n "$mnc" ] || mnc=$eem_mnc
            [ -n "$tac" ] || tac=$eem_tac
            [ -n "$pci" ] || pci=$eem_pci
            [ -n "$dl_earfcn" ] || dl_earfcn=$eem_dl_earfcn
            [ -n "$band_raw" ] || band_raw=$eem_band
            [ -n "$bandwidth_raw" ] || bandwidth_raw=$eem_dl_bandwidth
            [ -n "$cell_id" ] || cell_id=$eem_cell_id

            duplex=$(openluat_lte_duplex_mode "$band_raw")
            band=$(printf '%s' "$band_raw" | tr -d '[:space:]' | sed 's/^LTE//; s/^[Bb]//')
            [ -n "$band" ] && band="LTE B$band"
            bandwidth=$(openluat_lte_bandwidth "$bandwidth_raw")
            if [ "$duplex" = "TDD" ]; then
                ul_bandwidth=$bandwidth
            fi
            network_mode="LTE Mode"

            if [ -n "$rsrp_raw" ]; then
                rsrp=$(openluat_normalize_rsrp "$rsrp_raw")
            elif [ -z "$rsrp" ] && [ -n "$eem_rsrp_raw" ]; then
                rsrp=$(openluat_normalize_rsrp "$eem_rsrp_raw")
            fi
            if [ -n "$rsrq_raw" ]; then
                rsrq=$(openluat_normalize_rsrq "$rsrq_raw")
            elif [ -z "$rsrq" ] && [ -n "$eem_rsrq_raw" ]; then
                rsrq=$(openluat_normalize_rsrq "$eem_rsrq_raw")
            fi
            sinr=$(openluat_number_in_range "$eem_sinr_raw" -20 30)
            cqi=$(openluat_number_in_range "$eem_cqi_raw" 0 15)
            tx_power=$(openluat_number_in_range "$eem_tx_power_raw" -60 60)
            [ -n "$tx_power" ] && tx_power="$tx_power dBm"
            if [ -z "$rssi" ]; then
                rssi=$(openluat_number_in_range "$eem_rssi_raw" -140 -20)
            fi

            add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
            add_plain_info_entry "Duplex Mode" "$duplex" "Duplex Mode"
            add_plain_info_entry "MCC" "$mcc" "Mobile Country Code"
            add_plain_info_entry "MNC" "$mnc" "Mobile Network Code"
            add_plain_info_entry "TAC" "$tac" "Tracking Area Code"
            add_plain_info_entry "Cell ID" "$cell_id" "Cell ID"
            add_plain_info_entry "Physical Cell ID" "$pci" "Physical Cell ID"
            add_plain_info_entry "EARFCN" "$dl_earfcn" "E-UTRA Absolute Radio Frequency Channel Number"
            add_plain_info_entry "Band" "$band" "Band"
            add_plain_info_entry "UL Bandwidth" "$ul_bandwidth" "UL Bandwidth"
            add_plain_info_entry "DL Bandwidth" "$bandwidth" "DL Bandwidth"
            add_bar_info_entry "RSRP" "$rsrp" "Reference Signal Received Power" -141 -44 dBm
            add_bar_info_entry "RSRQ" "$rsrq" "Reference Signal Received Quality" -20 -3 dB
            add_bar_info_entry "SINR" "$sinr" "Signal to Interference plus Noise Ratio" -20 30 dB
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            add_plain_info_entry "CQI" "$cqi" "Channel Quality Indicator"
            add_plain_info_entry "TX Power" "$tx_power" "TX Power"
            ;;
        GSM)
            network_mode="GSM Mode"
            add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
            add_plain_info_entry "MCC" "$mcc" "Mobile Country Code"
            add_plain_info_entry "MNC" "$mnc" "Mobile Network Code"
            add_plain_info_entry "LAC" "$lac" "Location Area Code"
            add_plain_info_entry "Cell ID" "$cell_id" "Cell ID"
            add_plain_info_entry "BSIC" "$bsic" "Base Station Identity Code"
            add_plain_info_entry "ARFCN" "$arfcn" "Absolute Radio-Frequency Channel Number"
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            ;;
        *)
            add_plain_info_entry "network_mode" "$serving_rat" "Network Mode"
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            add_bar_info_entry "RSRP" "$rsrp" "Reference Signal Received Power" -141 -44 dBm
            add_bar_info_entry "RSRQ" "$rsrq" "Reference Signal Received Quality" -20 -3 dB
            ;;
    esac
}

get_dns()
{
    local cid response dns_values ipv4_dns1 ipv4_dns2

    cid=${pdp_index:-5}
    response=$(cmd_openluat_cgcontrdp "$at_port" "$cid")
    dns_values=$(printf '%s\n' "$response" | openluat_parse_cgcontrdp_dns "$cid")
    ipv4_dns1=$(printf '%s\n' "$dns_values" | sed -n '1p')
    ipv4_dns2=$(printf '%s\n' "$dns_values" | sed -n '2p')

    openluat_is_ipv4 "$ipv4_dns1" || ipv4_dns1=""
    openluat_is_ipv4 "$ipv4_dns2" || ipv4_dns2=""
    [ "$ipv4_dns1" = "0.0.0.0" ] && ipv4_dns1=""
    [ "$ipv4_dns2" = "0.0.0.0" ] && ipv4_dns2=""

    json_add_object "dns"
    json_add_string "ipv4_dns1" "$ipv4_dns1"
    json_add_string "ipv4_dns2" "$ipv4_dns2"
    json_add_string "ipv6_dns1" ""
    json_add_string "ipv6_dns2" ""
    json_close_object
}
