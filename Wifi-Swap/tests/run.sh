#!/bin/bash
# Disposable-card tests for Wifi-Swap. No real card or credentials are touched.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CARD="$(mktemp -d)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok  - $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL- $1"; }
chk(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }
finish(){ rm -rf "$CARD"; }
trap finish EXIT INT TERM

mkdir -p "$CARD/Scripts/.wifi-swap/profiles" "$CARD/linux" "$CARD/fake"
cp "$HERE/Scripts/wifi-swap.sh" "$CARD/Scripts/wifi-swap.sh"

cat > "$CARD/Scripts/wifi.sh" <<'EOF_WIFI'
#!/usr/bin/env bash
# Test double for the official helper's WIFI_LIBRARY_ONLY API.
WIFI_LIBRARY_ONLY="${WIFI_LIBRARY_ONLY:-0}"
INTERFACE="wlan0"
printMsgs(){ printf '%b\n' "$2" >&2; }
ensure_wpa_conf(){ mkdir -p "$(dirname "$WPA_CONF")"; [[ -f "$WPA_CONF" ]] || printf 'ctrl_interface=/run/wpa_supplicant\nupdate_config=1\n' > "$WPA_CONF"; }
wpa_conf_validation_error(){ return 0; }
is_valid_country_code(){ [[ "$1" =~ ^[A-Z]{2}$ && "$1" != "ZZ" ]]; }
get_country_code(){ awk -F= '/^country=/{print $2;exit}' "$WPA_CONF" 2>/dev/null; }
set_country_code(){
  local code="$1" tmp="${WPA_CONF}.country"
  awk -v code="$code" 'BEGIN{done=0} /^country=/{if(!done){print "country=" code;done=1};next} {print} END{if(!done)print "country=" code}' "$WPA_CONF" > "$tmp" && mv "$tmp" "$WPA_CONF"
}
apply_regulatory_country(){ printf 'country:%s\n' "$1" >> "$WIFI_SWAP_ROOT/fake/calls"; [[ "${FAKE_FAIL_COUNTRY:-}" != "$1" ]]; }
detect_interface(){ INTERFACE=wlan0; return 0; }
find_wireless_interface_once(){ printf 'wlan0\n'; }
current_ssid(){ cat "$WIFI_SWAP_ROOT/fake/current_ssid" 2>/dev/null || true; }
current_ip(){ cat "$WIFI_SWAP_ROOT/fake/current_ip" 2>/dev/null || true; }
string_to_wpa_hex(){ printf '%s' "$1" | od -An -tx1 | tr -d ' \n'; }
reload_wpa_supplicant(){ return 0; }
apply_wifi_settings(){
  printf 'connect:%s:%s\n' "$1" "$2" >> "$WIFI_SWAP_ROOT/fake/calls"
  if [[ "${FAKE_FAIL_SSID:-}" == "$1" ]]; then return 1; fi
  printf '%s\n' "$1" > "$WIFI_SWAP_ROOT/fake/current_ssid"
  printf '192.0.2.44\n' > "$WIFI_SWAP_ROOT/fake/current_ip"
  return 0
}
set_interface_state(){ return 0; }
show_infobox(){ printf 'info:%s\n' "$1" >> "$WIFI_SWAP_ROOT/fake/calls"; }
wait_for_association(){
  if [[ "${FAKE_FAIL_SSID:-}" == "$1" ]]; then return 1; fi
  printf '%s\n' "$1" > "$WIFI_SWAP_ROOT/fake/current_ssid"
  printf '%s\n' "$1"
}
preserve_ssh_client_route(){ return 0; }
start_dhcp_lease_request(){ return 0; }
wait_for_ipv4_lease(){ printf '192.0.2.44\n' > "$WIFI_SWAP_ROOT/fake/current_ip"; printf '192.0.2.44\n'; }
connection_health_report(){ printf 'test connection healthy\n'; }
[[ "$WIFI_LIBRARY_ONLY" == "1" ]] && return 0 2>/dev/null
EOF_WIFI
chmod 755 "$CARD/Scripts/wifi.sh" "$CARD/Scripts/wifi-swap.sh"

cat > "$CARD/fake/wpa_cli" <<'EOF_WPA_CLI'
#!/bin/sh
for last do :; done
case "$*" in
  *" list_networks") printf 'network id\tssid\tbssid\tflags\n7\tHome Test\tany\t\n8\tHotspot Test\tany\t\n' ;;
  *" get_network 7 id_str") printf '"wifi-swap:home"\n' ;;
  *" get_network 8 id_str") printf '"wifi-swap:hotspot"\n' ;;
  *" select_network 7") printf 'OK\n' ;;
  *" select_network 8") printf 'OK\n' ;;
  *" enable_network all") printf 'OK\n' ;;
  *) printf 'FAIL\n' ;;
esac
EOF_WPA_CLI
chmod 755 "$CARD/fake/wpa_cli"

cat > "$CARD/linux/wpa_supplicant.conf" <<'EOF_WPA'
country=US
ctrl_interface=/run/wpa_supplicant
update_config=1

# An official/unowned network must always survive.
network={
    ssid=4f6666696369616c204e6574776f726b
    psk=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
}
EOF_WPA

OUT=$(WIFI_SWAP_ROOT="$CARD" bash "$CARD/Scripts/wifi-swap.sh" 2>&1)
chk "empty Registry gives setup guidance" 'printf "%s" "$OUT" | grep -q "No Wifi-Swap profiles yet"'
chk "help works without touching networking" 'WIFI_SWAP_ROOT="/does/not/exist" bash "$CARD/Scripts/wifi-swap.sh" --help | grep -q "Create WiFi profiles"'

make_profile(){
  local id="$1" label="$2" ssid="$3" hex="$4" country="$5" psk="$6"
  local dir="$CARD/Scripts/.wifi-swap/profiles/$id"
  mkdir -p "$dir"
  printf '%s\n' "$label" > "$dir/label.txt"
  printf '%s\n' "$ssid" > "$dir/ssid.txt"
  printf '%s\n' "$hex" > "$dir/ssid.hex"
  printf '%s\n' "$country" > "$dir/country.txt"
  printf 'wpa\n' > "$dir/security.txt"
  printf '0\n' > "$dir/hidden.txt"
  cat > "$dir/network.conf" <<EOF_PROFILE
network={
    ssid=$hex
    psk=$psk
}
EOF_PROFILE
}

make_profile home "Home" "Home Test" 486f6d652054657374 US bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
make_profile hotspot "Phone Hotspot" "Hotspot Test" 486f7473706f742054657374 CA cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

LIST=$(WIFI_SWAP_ROOT="$CARD" bash "$CARD/Scripts/wifi-swap.sh" --list)
chk "Registry profiles list independently of Profiler" 'printf "%s" "$LIST" | grep -q "Home Test" && printf "%s" "$LIST" | grep -q "Phone Hotspot"'

HOME_OUT=$(PATH="$CARD/fake:$PATH" WIFI_SWAP_ROOT="$CARD" bash "$CARD/Scripts/wifi-swap.sh" --connect home 2>&1) || printf '%s\n' "$HOME_OUT"
chk "selected profile connects by its exact managed ID" 'grep -q "id_str=\"wifi-swap:home\"" "$CARD/linux/wpa_supplicant.conf" && grep -q "priority=999" "$CARD/linux/wpa_supplicant.conf"'
chk "successful profile becomes the Last connected choice" '[ "$(cat "$CARD/Scripts/.wifi-swap/active")" = home ]'
chk "managed block is clearly owned" 'grep -q "# WIFI-SWAP:BEGIN:home" "$CARD/linux/wpa_supplicant.conf"'
chk "unowned official network is preserved" 'grep -q "4f6666696369616c204e6574776f726b" "$CARD/linux/wpa_supplicant.conf"'
chk "country is applied through official helper" '[ "$(awk -F= "/^country=/{print \$2;exit}" "$CARD/linux/wpa_supplicant.conf")" = US ]'

BEFORE=$(cksum "$CARD/linux/wpa_supplicant.conf")
PATH="$CARD/fake:$PATH" FAKE_FAIL_SSID="Hotspot Test" WIFI_SWAP_ROOT="$CARD" bash "$CARD/Scripts/wifi-swap.sh" --connect hotspot >/dev/null 2>&1 || true
AFTER=$(cksum "$CARD/linux/wpa_supplicant.conf")
chk "failed switch restores exact prior standard configuration" '[ "$BEFORE" = "$AFTER" ]'
chk "failed switch does not change Last connected profile" '[ "$(cat "$CARD/Scripts/.wifi-swap/active")" = home ]'
chk "failed country switch restores previous country" '[ "$(awk -F= "/^country=/{print \$2;exit}" "$CARD/linux/wpa_supplicant.conf")" = US ]'

mkdir -p "$CARD/Scripts/.wifi-swap/profiles/broken"
printf 'Broken\n' > "$CARD/Scripts/.wifi-swap/profiles/broken/label.txt"
printf 'Mismatch\n' > "$CARD/Scripts/.wifi-swap/profiles/broken/ssid.txt"
printf '4d69736d61746368\n' > "$CARD/Scripts/.wifi-swap/profiles/broken/ssid.hex"
printf 'US\n' > "$CARD/Scripts/.wifi-swap/profiles/broken/country.txt"
cat > "$CARD/Scripts/.wifi-swap/profiles/broken/network.conf" <<'EOF_BAD'
network={
    ssid=77726f6e67
    key_mgmt=NONE
}
EOF_BAD
BEFORE=$(cksum "$CARD/linux/wpa_supplicant.conf")
WIFI_SWAP_ROOT="$CARD" bash "$CARD/Scripts/wifi-swap.sh" --connect broken >/dev/null 2>&1 || true
AFTER=$(cksum "$CARD/linux/wpa_supplicant.conf")
chk "mismatched Registry data is rejected before replacement" '[ "$BEFORE" = "$AFTER" ]'

if grep -Rqi 'password123\|realssid' "$CARD/Scripts/.wifi-swap"; then no "fixtures contain no plaintext password"; else ok "Registry stores no plaintext password"; fi

echo
echo "WIFI-SWAP RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
