#!/bin/bash
# Regression test: neighbour scans wait for the driver instead of a fixed time.
#
# Scans go a few channels at a time (see gentle-scans.sh). Until each one ends, `wl scanresults` may
# answer "Not Ready" (3006.102 / driver 17.10 routers are slow), so each group is polled for up to 15 s;
# a group the radio refuses (busy with another scan) is retried for up to 20 s, and a band stops
# starting new groups after 200 s. Results are read 2 s into a group at the earliest.
#
# A stand-in wl simulates slow, busy, silent and switched-off radios, on a fake clock (date +%s and
# sleep), so the test takes seconds. Runs with Merlin's BusyBox commands only, like large-history.sh.
#
# Usage: .github/tests/scan-wait.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, python3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::scan-wait.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::scan-wait.sh needs sqlite3 installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
R=$t/root; F=$t/fix; D=$t/data
mkdir -p "$R/jffs/addons/wifiinsight" "$R/www/user" "$R/tmp" "$F" "$D" "$t/bin"
cp "$script" "$R/jffs/addons/wifiinsight/wifiinsight.sh"
printf 'SQLITE="%s"\nDATA_DIR="%s"\n' "$sqlite" "$D" > "$R/jffs/addons/wifiinsight/config"
"$bb" --list > "$t/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$t/bb.list"; then ln -s "$bb" "$t/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$t/bin/$a"
	fi
done
rm -f "$t/bin/date" "$t/bin/sleep" "$t/bin/logger"

# Fake clock: date +%s reads it, sleep moves it on.
echo 1800000000 > "$F/clock"
cat > "$t/bin/date" <<EOF
#!$bb sh
if [ "\$*" = "+%s" ]; then cat "$F/clock"; else exec "$bb" date "\$@"; fi
EOF
cat > "$t/bin/sleep" <<EOF
#!$bb sh
echo \$(( \$(cat "$F/clock") + \$1 )) > "$F/clock"
EOF
printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$F" > "$t/bin/logger"
cat > "$t/bin/nvram" <<'EOF'
#!/bin/sh
case "$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; wl0_ssid|wl1_ssid) echo HomeNet ;; esac
EOF
# Stand-in driver. Per interface, in $F: <ifc>.ready (seconds from the scan until results, or "never"),
# <ifc>.busy (scan refused until this clock time), <ifc>.empty (scan ends with nothing heard),
# <ifc>.down (radio off), <ifc>.reject (a channel group it always refuses).
cat > "$t/bin/wl" <<EOF
#!$bb sh
F="$F"; ifc=\$2; now=\$(cat "\$F/clock")
case "\$3" in
	isup) [ -f "\$F/\$ifc.down" ] && echo 0 || echo 1 ;;
	chanspec) [ "\$ifc" = eth6 ] && echo "6 (0x1006)" || echo "100/80 (0xe06a)" ;;
	channels) [ "\$ifc" = eth6 ] && echo "1 2 3 4 5 6 7 8 9 10 11" || echo "36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140" ;;
	scan)
		if [ -f "\$F/\$ifc.busy" ] && [ "\$now" -lt "\$(cat "\$F/\$ifc.busy")" ]; then echo "wl: Busy" >&2; exit 1; fi
		if [ -f "\$F/\$ifc.reject" ] && [ "\$5" = "\$(cat "\$F/\$ifc.reject")" ]; then echo "wl: Scan Rejected" >&2; exit 1; fi
		echo "\$now" > "\$F/\$ifc.started" ;;
	scanresults)
		r=\$(cat "\$F/\$ifc.ready" 2>/dev/null || echo 2); s=\$(cat "\$F/\$ifc.started" 2>/dev/null || echo 0)
		if [ "\$r" = never ] || [ "\$now" -lt \$(( s + r )) ]; then echo "wl: Not Ready" >&2; exit 1; fi
		[ -f "\$F/\$ifc.empty" ] || cat "\$F/results_\$ifc.txt" ;;
	*) exit 1 ;;
esac
EOF
chmod +x "$t/bin/date" "$t/bin/sleep" "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl"
net() {   # ssid bssid rssi "Channel: x/w" chanspec-line primary
	printf 'SSID: "%s"\nMode: Managed\tRSSI: %s dBm\tSNR: 30 dB\tnoise: -92 dBm\tFlags: RSSI on-channel \tChannel: %s\nBSSID: %s\tCapability: ESS ShortSlot\nRSN (WPA2):\n\tAKM Suites(1): WPA2-PSK\nHE Capable:\n\tChanspec: %s\n\tPrimary channel: %s\nQBSS Channel Utilization: 0x26 (15 %%)\n\n' "$1" "$3" "$4" "$2" "$5" "$6"
}
{ net Neighbour-24 02:00:00:00:24:01 -62 6 "2.4GHz channel 6 20MHz (0x1006)" 6
  net Cafe-24 02:00:00:00:24:02 -75 11 "2.4GHz channel 11 20MHz (0x100b)" 11; } > "$F/results_eth6.txt"
{ net Neighbour-5 02:00:00:00:05:01 -66 100/80 "5GHz channel 106 80MHz (0xe06a)" 100
  net Cafe-5 02:00:00:00:05:02 -80 36/160 "5GHz channel 50 160MHz (0xe832)" 36; } > "$F/results_eth7.txt"

awk '/^init_db\(\) \{/ { f = 1 } f && /^EOF$/ { exit } f && p { print } f && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
"$sqlite" "$D/wifiinsight.db" < "$t/schema.sql"
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@"; }

fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
# case: name, then settings for eth6 and eth7; checks the result line for each band and the 5 GHz rows
case_() {   # name want2g want5g
	rm -f "$F"/*.started; : > "$F/log"
	b5=$("$sqlite" "$D/wifiinsight.db" "SELECT count(*) FROM scans WHERE band='5g'")
	out=$(run scan 2>&1) || true
	a5=$("$sqlite" "$D/wifiinsight.db" "SELECT count(*) FROM scans WHERE band='5g'")
	g2=$(printf '%s\n' "$out" | sed -n 's/^  2g (eth6): //p'); g5=$(printf '%s\n' "$out" | sed -n 's/^  5g (eth7): //p')
	if [ "$g2" = "$2" ] && [ "$g5" = "$3" ]; then ok "$1: 2g '$g2', 5g '$g5'"
	else bad "$1"; echo "      want 2g '$2', 5g '$3'"; echo "      got  2g '$g2', 5g '$g5'"; printf '%s\n' "$out" | sed 's/^/      | /'; fi
	case "$3" in
		ok*) [ "$a5" -gt "$b5" ] && ok "$1: 5 GHz scan saved" || bad "$1: 5 GHz scan not saved" ;;
		*)   [ "$a5" -eq "$b5" ] && ok "$1: previous 5 GHz scan kept" || bad "$1: 5 GHz rows changed" ;;
	esac
	grep -q "^scan 5g (eth7): $3\$" "$F/log" && ok "$1: logged" || { bad "$1: syslog line"; cat "$F/log"; }
	python3 - "$R/www/user/wifiinsight/scanstate.htm" "$3" <<'EOF' && ok "$1: page told why" || bad "$1: scanstate.htm"
import json, sys
s = json.load(open(sys.argv[1])); want = sys.argv[2]
r, _, note = want.partition(', ')
sys.exit(0 if s['state'] == 'done' and s['bands']['5g'] == r and s['notes']['5g'] == note else 1)
EOF
}
reset() { rm -f "$F"/*.ready "$F"/*.busy "$F"/*.empty "$F"/*.down "$F"/*.reject; }

# 2.4 GHz: 3 groups (1-4, 5-8, 9-11); 5 GHz: 10 groups of two. A group takes max(2 s, its scan), plus
# 1 s back on the router's channel before each group after the first.
reset; echo 2 > "$F/eth6.ready"; echo 2 > "$F/eth7.ready"
case_ "a quick driver (RT-AX86U-like)" "ok, 2 networks in 8 s" "ok, 2 networks in 29 s"
reset; echo 6 > "$F/eth7.ready"
case_ "a slow driver: 6 s per group (17.10)" "ok, 2 networks in 8 s" "ok, 2 networks in 69 s"
reset; echo 20 > "$F/eth7.ready"
case_ "5 GHz groups never finish in time" "ok, 2 networks in 8 s" "empty, wl said \"Not Ready\" for 15 s"
reset; echo $(( $(cat "$F/clock") + 15 )) > "$F/eth7.busy"
case_ "5 GHz busy for a while (acsd, Smart Connect)" "ok, 2 networks in 8 s" "ok, 2 networks in 37 s"
reset; echo 99999999999 > "$F/eth7.busy"
case_ "5 GHz always busy" "ok, 2 networks in 8 s" "busy, wl said \"Busy\" for 20 s"
reset; echo 100,104 > "$F/eth7.reject"
case_ "one 5 GHz group refused" "ok, 2 networks in 8 s" "ok, 2 networks in 47 s, 1 of 10 channel groups not scanned (wl said \"Scan Rejected\" for 20 s)"
reset; touch "$F/eth7.empty"
case_ "5 GHz hears nothing" "ok, 2 networks in 8 s" "empty, no networks heard in 29 s"
reset; touch "$F/eth7.down"
case_ "5 GHz radio off" "ok, 2 networks in 8 s" "off"
reset; echo never > "$F/eth6.ready"
case_ "2.4 GHz groups never finish" "empty, wl said \"Not Ready\" for 15 s" "ok, 2 networks in 29 s"

[ $fail -eq 0 ] && echo "Scan wait: all checks passed." || { echo "::error::Scan wait: some checks failed."; exit 1; }
