#!/usr/bin/env bash
# Wifi-Swap for MiSTer FPGA
# GPL-3.0-or-later; Copyright (C) 2026 MikeyVids.
#
# This is a profile picker layered on the official MiSTer wifi.sh. It does not
# replace MiSTer's Wi-Fi engine or store credentials in MiSTer.ini.

set -u

readonly WS_VERSION="0.3.0"
readonly WS_ROOT="${WIFI_SWAP_ROOT:-/media/fat}"
readonly WS_STATE="${WIFI_SWAP_STATE:-$WS_ROOT/Scripts/.wifi-swap}"
readonly WS_PROFILES="$WS_STATE/profiles"
readonly WS_ACTIVE="$WS_STATE/active"
readonly WS_LOCK="$WS_STATE/lock"
readonly WS_WPA="${WIFI_SWAP_WPA_CONF:-$WS_ROOT/linux/wpa_supplicant.conf}"
readonly WS_CACHED_HELPER="$WS_STATE/wifi-helper.sh"
readonly WS_HELPER_URL="https://raw.githubusercontent.com/MiSTer-devel/Scripts_MiSTer/master/other_authors/wifi.sh"
WS_HELPER=""
WS_SYNC_BACKUP=""
WS_LOCK_HELD=0

ws_console() { printf '%s\n' "$*"; }

ws_message() {
    local message="$1"
    if declare -F printMsgs >/dev/null 2>&1; then
        printMsgs "dialog" "$message"
    else
        ws_console "$message"
    fi
}

ws_find_helper() {
    local candidate
    if [[ -n "${WIFI_SWAP_WIFI_HELPER:-}" && -f "$WIFI_SWAP_WIFI_HELPER" ]]; then
        printf '%s\n' "$WIFI_SWAP_WIFI_HELPER"
        return 0
    fi

    for candidate in \
        "$WS_CACHED_HELPER" \
        "$WS_ROOT/Scripts/wifi.sh" \
        "$WS_ROOT/Scripts/WiFi.sh" \
        "$WS_ROOT/Scripts/other_authors/wifi.sh"
    do
        [[ -f "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

ws_helper_compatible() {
    [ -f "$1" ] &&
        grep -q 'WIFI_LIBRARY_ONLY' "$1" 2>/dev/null &&
        grep -q '^apply_wifi_settings()' "$1" 2>/dev/null &&
        grep -q '^reload_wpa_supplicant()' "$1" 2>/dev/null
}

ws_fetch_current_helper() {
    local tmp="$WS_CACHED_HELPER.download.$$"
    mkdir -p "$WS_STATE" || return 1
    if command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 15 --max-time 90 "$WS_HELPER_URL" -o "$tmp" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
        wget -T 90 -O "$tmp" "$WS_HELPER_URL" 2>/dev/null || true
    fi
    ws_helper_compatible "$tmp" || { rm -f "$tmp"; return 1; }
    bash -n "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$WS_CACHED_HELPER" || return 1
    chmod 755 "$WS_CACHED_HELPER" 2>/dev/null || true
}

ws_load_official_wifi() {
    WS_HELPER=$(ws_find_helper) || {
        ws_console "No compatible WiFi helper was found. Trying to cache the current official helper..."
        ws_fetch_current_helper || {
            ws_console "Could not download it. Connect Ethernet or install/update wifi.sh through MiSTer Downloader, then retry."
            return 1
        }
        WS_HELPER="$WS_CACHED_HELPER"
    }
    if ! ws_helper_compatible "$WS_HELPER"; then
        ws_console "The installed WiFi helper is older than Wifi-Swap's tested interface."
        ws_console "Trying to cache the current official helper without replacing your installed script..."
        if ws_fetch_current_helper; then WS_HELPER="$WS_CACHED_HELPER"
        else
            ws_console "Could not fetch it. Connect with Ethernet or another working network, then retry."
            ws_console "You can also update wifi.sh through MiSTer Downloader."
            return 1
        fi
    fi

    # The official helper honors these variables before marking WPA_CONF
    # readonly. Library mode exposes its tested connection functions without
    # opening its own menu.
    WPA_CONF="$WS_WPA"
    WIFI_LIBRARY_ONLY=1
    export WPA_CONF WIFI_LIBRARY_ONLY
    # shellcheck source=/dev/null
    . "$WS_HELPER" || return 1
}

ws_profile_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]]; }

ws_read_one_line() {
    local file="$1" value=""
    [[ -f "$file" ]] || return 1
    IFS= read -r value < "$file" || [[ -n "$value" ]] || return 1
    value=${value%$'\r'}
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
    printf '%s\n' "$value"
}

ws_profile_field() { ws_read_one_line "$WS_PROFILES/$1/$2.txt"; }

ws_profile_ids() {
    local dir id
    [[ -d "$WS_PROFILES" ]] || return 0
    for dir in "$WS_PROFILES"/*; do
        [[ -d "$dir" ]] || continue
        id=$(basename "$dir")
        ws_profile_ok "$id" || continue
        [[ -f "$dir/network.conf" ]] || continue
        printf '%s\n' "$id"
    done
}

ws_profile_count() { ws_profile_ids | awk 'END { print NR + 0 }'; }

ws_lock() {
    local now stamp age
    mkdir -p "$WS_STATE" "$WS_PROFILES" 2>/dev/null || return 1
    now=$(date +%s)
    if mkdir "$WS_LOCK" 2>/dev/null; then
        printf '%s\n' "$now" > "$WS_LOCK/started"
        WS_LOCK_HELD=1
        return 0
    fi
    stamp=$(ws_read_one_line "$WS_LOCK/started" 2>/dev/null || printf '0')
    [[ "$stamp" =~ ^[0-9]+$ ]] || stamp=0
    age=$((now - stamp))
    if [[ "$age" -gt 300 ]]; then
        rm -rf "$WS_LOCK" 2>/dev/null || return 1
        mkdir "$WS_LOCK" 2>/dev/null || return 1
        printf '%s\n' "$now" > "$WS_LOCK/started"
        WS_LOCK_HELD=1
        return 0
    fi
    ws_message "Wifi-Swap is already running. Wait a moment and try again."
    return 1
}

ws_unlock() {
    [[ "$WS_LOCK_HELD" -eq 1 ]] || return 0
    rm -rf "$WS_LOCK" 2>/dev/null || true
    WS_LOCK_HELD=0
}

ws_strip_managed_blocks() {
    local input="$1" output="$2"
    awk '
        /^# WIFI-SWAP:BEGIN:/ {
            if (managed) bad=1
            managed=1
            next
        }
        /^# WIFI-SWAP:END:/ {
            if (!managed) bad=1
            managed=0
            next
        }
        !managed { print }
        END { if (managed || bad) exit 42 }
    ' "$input" > "$output"
}

ws_base_has_hex_ssid() {
    local file="$1" wanted
    wanted=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
    awk -v wanted="$wanted" '
        {
            line=$0
            sub(/^[[:space:]]*/, "", line)
            if (line !~ /^ssid[[:space:]]*=/) next
            sub(/^ssid[[:space:]]*=[[:space:]]*/, "", line)
            sub(/[[:space:]]*#.*/, "", line)
            gsub(/[[:space:]\r]/, "", line)
            if (tolower(line) == wanted) found=1
        }
        END { exit found ? 0 : 1 }
    ' "$file"
}

ws_sync_registry() {
    local selected="${1:-}" temp backup error dir id hex block priority

    ensure_wpa_conf || return 1
    error=$(wpa_conf_validation_error "$WPA_CONF")
    if [[ -n "$error" ]]; then
        ws_message "The standard WiFi configuration needs repair before Wifi-Swap can add profiles:\n\n$error\n\nRun the official wifi.sh → Repair WPA config."
        return 1
    fi

    backup=$(mktemp "${WPA_CONF}.wifi-swap.backup.XXXXXX") || return 1
    cp -p "$WPA_CONF" "$backup" || { rm -f "$backup"; return 1; }
    temp=$(mktemp "$(dirname "$WPA_CONF")/.wifi-swap.tmp.XXXXXX") || {
        rm -f "$backup"
        return 1
    }

    if ! ws_strip_managed_blocks "$WPA_CONF" "$temp"; then
        rm -f "$temp" "$backup"
        ws_message "Wifi-Swap found an incomplete ownership marker in wpa_supplicant.conf. No change was made. Restore a known-good backup or remove only the broken WIFI-SWAP marker block."
        return 1
    fi

    for dir in "$WS_PROFILES"/*; do
        [[ -d "$dir" && -f "$dir/network.conf" ]] || continue
        id=$(basename "$dir")
        ws_profile_ok "$id" || continue
        hex=$(ws_read_one_line "$dir/ssid.hex" 2>/dev/null || true)
        [[ "$hex" =~ ^([0-9A-Fa-f]{2}){1,32}$ ]] || {
            rm -f "$temp" "$backup"
            ws_message "Profile '$id' has an invalid SSID. Open Wifi-Swap Registry and save it again."
            return 1
        }
        block="$dir/network.conf"
        if ! grep -Eiq "^[[:space:]]*ssid[[:space:]]*=[[:space:]]*${hex}[[:space:]]*$" "$block"; then
            rm -f "$temp" "$backup"
            ws_message "Profile '$id' does not match its saved network block. Open Wifi-Swap Registry and save it again."
            return 1
        fi

        [ "$id" = "$selected" ] && priority=999 || priority=10
        {
            printf '\n# WIFI-SWAP:BEGIN:%s\n' "$id"
            awk -v ident="wifi-swap:$id" -v priority="$priority" '
                /^[[:space:]]*}[[:space:]]*$/ && !done {
                    print "    id_str=\"" ident "\""
                    print "    priority=" priority
                    done=1
                }
                { print }
            ' "$block"
            printf '# WIFI-SWAP:END:%s\n' "$id"
        } >> "$temp" || {
            rm -f "$temp" "$backup"
            return 1
        }
    done

    error=$(wpa_conf_validation_error "$temp")
    if [[ -n "$error" ]]; then
        rm -f "$temp" "$backup"
        ws_message "Wifi-Swap refused to install an invalid WiFi configuration:\n\n$error\n\nThe original file was left untouched."
        return 1
    fi
    chmod 600 "$temp" || { rm -f "$temp" "$backup"; return 1; }
    mv -f "$temp" "$WPA_CONF" || { rm -f "$temp" "$backup"; return 1; }
    sync || true
    WS_SYNC_BACKUP="$backup"
    return 0
}

ws_restore_config() {
    local backup="$1"
    local temp
    [[ -n "$backup" && -f "$backup" ]] || return 1
    temp=$(mktemp "$(dirname "$WPA_CONF")/.wifi-swap.rollback.XXXXXX") || return 1
    cp -p "$backup" "$temp" || { rm -f "$temp"; return 1; }
    chmod 600 "$temp" || { rm -f "$temp"; return 1; }
    mv -f "$temp" "$WPA_CONF" || { rm -f "$temp"; return 1; }
    sync || true
}

ws_save_active() {
    local id="$1" temp
    temp=$(mktemp "$WS_STATE/.active.tmp.XXXXXX") || return 1
    printf '%s\n' "$id" > "$temp" || { rm -f "$temp"; return 1; }
    chmod 600 "$temp" || { rm -f "$temp"; return 1; }
    mv -f "$temp" "$WS_ACTIVE" || { rm -f "$temp"; return 1; }
    sync || true
}

ws_status() {
    local current="" ip="" active="" label="" count
    count=$(ws_profile_count)
    [[ -f "$WS_ACTIVE" ]] && active=$(ws_read_one_line "$WS_ACTIVE" 2>/dev/null || true)
    if declare -F find_wireless_interface_once >/dev/null 2>&1; then
        INTERFACE=$(find_wireless_interface_once 2>/dev/null || printf '%s' "${INTERFACE:-wlan0}")
        current=$(current_ssid 2>/dev/null || true)
        ip=$(current_ip 2>/dev/null || true)
    fi
    if [[ -n "$active" && -d "$WS_PROFILES/$active" ]]; then
        label=$(ws_profile_field "$active" label 2>/dev/null || true)
    fi
    ws_console "Wifi-Swap $WS_VERSION"
    ws_console "Registry profiles: $count"
    ws_console "Selected profile: ${label:-${active:-(none)}}"
    ws_console "Connected network: ${current:-(not connected)}"
    ws_console "IPv4 address: ${ip:-(none)}"
}

ws_diagnose() {
    local error=""
    detect_interface >/dev/null 2>&1 || true
    error=$(wpa_conf_validation_error "$WPA_CONF" 2>/dev/null || true)
    ws_console "Wifi-Swap $WS_VERSION diagnostics (passwords omitted)"
    ws_console "Helper: $WS_HELPER"
    ws_console "Interface: ${INTERFACE:-(not detected)}"
    ws_console "Adapter: $([ -n "${INTERFACE:-}" ] && [ -e "/sys/class/net/$INTERFACE" ] && echo present || echo not-found)"
    ws_console "Registry profiles: $(ws_profile_count)"
    ws_console "WiFi config: $WPA_CONF"
    ws_console "Config check: ${error:-OK}"
    ws_console "Connected SSID: $(current_ssid 2>/dev/null || echo none)"
    ws_console "IPv4: $(current_ip 2>/dev/null || echo none)"
    ws_console "Managed blocks: $(grep -c '^# WIFI-SWAP:BEGIN:' "$WPA_CONF" 2>/dev/null || echo 0)"
    ws_console "Log this screen or photograph it; it contains no saved password."
}

ws_list() {
    local id label ssid country active="" marker
    [[ -f "$WS_ACTIVE" ]] && active=$(ws_read_one_line "$WS_ACTIVE" 2>/dev/null || true)
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        label=$(ws_profile_field "$id" label 2>/dev/null || printf '%s' "$id")
        ssid=$(ws_profile_field "$id" ssid 2>/dev/null || printf '?')
        country=$(ws_profile_field "$id" country 2>/dev/null || printf '?')
        marker=" "
        [[ "$id" == "$active" ]] && marker="*"
        printf '%s %-24s  SSID: %-24s  Country: %s  [%s]\n' "$marker" "$label" "$ssid" "$country" "$id"
    done < <(ws_profile_ids)
}

ws_choose() {
    local -a choices=()
    local id label ssid choice=""
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        label=$(ws_profile_field "$id" label 2>/dev/null || printf '%s' "$id")
        ssid=$(ws_profile_field "$id" ssid 2>/dev/null || printf '?')
        choices+=("$id" "$label — $ssid")
    done < <(ws_profile_ids)
    [[ ${#choices[@]} -gt 0 ]] || return 1

    if declare -F capture_dialog >/dev/null 2>&1 && command -v dialog >/dev/null 2>&1; then
        choice=$(capture_dialog dialog --backtitle "Wifi-Swap $WS_VERSION" --cancel-label "Exit" \
            --menu "Choose the WiFi profile MiSTer should use.\n\nChanging networks may end SSH, CIFS, or web sessions." \
            20 76 10 "${choices[@]}") || return 1
        printf '%s\n' "$choice"
        return 0
    fi

    ws_console "Choose a Wifi-Swap profile:"
    ws_list
    printf 'Profile ID (or blank to cancel): ' >&2
    IFS= read -r choice
    [[ -n "$choice" ]] || return 1
    printf '%s\n' "$choice"
}

ws_select_managed_network() {
    local wanted="wifi-swap:$1" tries=0 rows network_id saved_id
    command -v wpa_cli >/dev/null 2>&1 || return 1
    while [[ "$tries" -lt 8 ]]; do
        rows=$(wpa_cli -i "$INTERFACE" list_networks 2>/dev/null || true)
        while IFS=$'\t' read -r network_id _; do
            [[ "$network_id" =~ ^[0-9]+$ ]] || continue
            saved_id=$(wpa_cli -i "$INTERFACE" get_network "$network_id" id_str 2>/dev/null || true)
            saved_id="${saved_id#\"}"; saved_id="${saved_id%\"}"
            if [[ "$saved_id" == "$wanted" ]]; then
                wpa_cli -i "$INTERFACE" select_network "$network_id" 2>/dev/null | grep -qx OK
                return $?
            fi
        done <<< "$rows"
        sleep 1
        tries=$((tries + 1))
    done
    return 1
}

ws_apply_profile() {
    local id="$1" ssid="$2" hex="$3" associated ip health
    # Compatibility lane for a previously installed helper. Current helpers use
    # the ID-tagged path below; an older helper still gets its own public apply
    # function instead of a mysterious "command not found".
    if ! declare -F set_interface_state >/dev/null 2>&1 ||
       ! declare -F wait_for_association >/dev/null 2>&1 ||
       ! declare -F start_dhcp_lease_request >/dev/null 2>&1; then
        apply_wifi_settings "$ssid" "$hex"
        return $?
    fi
    set_interface_state up || return 1
    reload_wpa_supplicant || {
        ws_message "Could not reload the WiFi service on $INTERFACE."
        return 1
    }
    if ! ws_select_managed_network "$id"; then
        ws_message "The saved Wifi-Swap network did not load into $INTERFACE. No network was changed. Run Wifi-Swap --diagnose for a credential-free report."
        return 1
    fi
    show_infobox "Connecting $INTERFACE to $ssid..."
    associated=$(wait_for_association "$ssid") || {
        ws_message "The profile loaded, but $INTERFACE did not join '$ssid'. Check the password, country, signal, and whether the adapter supports this network."
        return 1
    }
    preserve_ssh_client_route
    ip -4 addr flush dev "$INTERFACE" scope global >/dev/null 2>&1 || true
    start_dhcp_lease_request || {
        ws_message "Joined '$associated', but could not ask the router for an IP address."
        return 1
    }
    ip=$(wait_for_ipv4_lease "$associated") || {
        ws_message "Joined '$associated', but the router did not provide an IP address."
        return 1
    }
    wpa_cli -i "$INTERFACE" enable_network all >/dev/null 2>&1 || true
    health=$(connection_health_report 2>/dev/null || true)
    ws_message "Successfully connected.\n\nInterface: $INTERFACE\nNetwork: $associated\nIP address: $ip\n\n$health"
}

ws_connect() {
    local id="$1" dir label ssid hex country old_country old_ssid old_hex="" old_ip=""
    dir="$WS_PROFILES/$id"
    ws_profile_ok "$id" && [[ -d "$dir" ]] || {
        ws_message "Unknown Wifi-Swap profile: $id"
        return 1
    }
    label=$(ws_profile_field "$id" label) || return 1
    ssid=$(ws_profile_field "$id" ssid) || return 1
    hex=$(ws_read_one_line "$dir/ssid.hex") || return 1
    country=$(ws_profile_field "$id" country) || return 1
    is_valid_country_code "$country" || {
        ws_message "Profile '$label' needs a valid two-letter country code. Open Wifi-Swap Registry and save it again."
        return 1
    }

    ws_lock || return 1
    trap ws_unlock EXIT
    trap 'ws_unlock; exit 130' INT TERM

    detect_interface || return 1
    old_country=$(get_country_code 2>/dev/null || true)
    old_ssid=$(current_ssid 2>/dev/null || true)
    old_ip=$(current_ip 2>/dev/null || true)
    [[ -n "$old_ssid" ]] && old_hex=$(string_to_wpa_hex "$old_ssid" 2>/dev/null || true)

    WS_SYNC_BACKUP=""
    ws_sync_registry "$id" || return 1
    if ! apply_regulatory_country "$country" || ! set_country_code "$country"; then
        ws_restore_config "$WS_SYNC_BACKUP" >/dev/null 2>&1 || true
        if is_valid_country_code "$old_country"; then
            apply_regulatory_country "$old_country" >/dev/null 2>&1 || true
        fi
        ws_message "Could not apply country=$country. The previous WiFi configuration was restored."
        return 1
    fi

    if ws_apply_profile "$id" "$ssid" "$hex"; then
        ws_save_active "$id" || ws_message "Connected to '$label', but could not save the Last connected label."
        rm -f "$WS_SYNC_BACKUP" 2>/dev/null || true
        trap - EXIT INT TERM
        ws_unlock
        return 0
    fi

    ws_restore_config "$WS_SYNC_BACKUP" >/dev/null 2>&1 || true
    if is_valid_country_code "$old_country"; then
        apply_regulatory_country "$old_country" >/dev/null 2>&1 || true
    fi
    reload_wpa_supplicant >/dev/null 2>&1 || true
    if [[ -n "$old_ssid" && -n "$old_hex" ]]; then
        apply_wifi_settings "$old_ssid" "$old_hex" >/dev/null 2>&1 || true
    fi
    rm -f "$WS_SYNC_BACKUP" 2>/dev/null || true
    ws_message "Could not connect to '$label'. Restored the previous WiFi configuration.\n\nPrevious network: ${old_ssid:-(none)}\nPrevious IPv4: ${old_ip:-(none)}"
    return 1
}

ws_help() {
    cat <<EOF
Wifi-Swap $WS_VERSION

Usage: wifi-swap.sh [--menu|--list|--status|--diagnose|--connect PROFILE_ID]

Create WiFi profiles with Wifi-Swap-Registry.html on a computer. Then run this
script on MiSTer to choose one. Player profiles from Profiler are unrelated.

Wifi-Swap uses the official MiSTer wifi.sh for adapter, WPA, DHCP, and health
handling. It never stores WiFi credentials in MiSTer.ini.
EOF
}

main() {
    local command="${1:---menu}" id count
    if [[ "$command" == "--help" || "$command" == "-h" ]]; then
        ws_help
        return 0
    fi
    ws_load_official_wifi || return 1
    mkdir -p "$WS_PROFILES" 2>/dev/null || return 1
    count=$(ws_profile_count)

    case "$command" in
        --status) ws_status ;;
        --diagnose|--diagnostics) ws_diagnose ;;
        --list) ws_list ;;
        --connect)
            id="${2:-}"
            [[ -n "$id" ]] || { ws_console "--connect needs a profile ID."; return 1; }
            ws_connect "$id"
            ;;
        --menu|"")
            if [[ "$count" -eq 0 ]]; then
                ws_message "No Wifi-Swap profiles yet.\n\n1. Open Wifi-Swap-Registry.html on a computer.\n2. Connect the whole MiSTer SD card.\n3. Add Home, Hotspot, or travel WiFi.\n4. Return to MiSTer and run Wifi-Swap again.\n\nThe official wifi.sh still works normally."
                return 0
            fi
            id=$(ws_choose) || return 0
            ws_connect "$id"
            ;;
        *)
            ws_help
            return 1
            ;;
    esac
}

main "$@"
status=$?
trap - EXIT INT TERM
ws_unlock
exit "$status"
