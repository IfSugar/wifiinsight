#!/bin/bash
# Regression test: scans the driver stops early, and per-channel figures it keeps between scans.
#
# On an RT-AX86U (3004.388) with traffic on its 5 GHz channel, the driver's full scan stopped after
# 36-104 of 36-140, every daytime scan, while `wl scan -c 108,...,140` scanned the rest fine. And the
# driver keeps each channel's last figures in `wl chanim_stats all` until a scan reaches it again,
# so a short scan still lists 108-140 with old figures. WiFi Insight now:
#  - stores figures only for channels the scan reached (changed since before it, or before one that did),
#  - scans the channels it didn't reach, and merges the networks heard,
#  - doesn't repeat a follow-up that reached nothing, and leaves drivers without per-channel figures alone.
#
# A stand-in driver keeps per-channel figures between scans and can stop a full scan after N channels.
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs, on a fake clock.
# Usage: .github/tests/short-scans.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::short-scans.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::short-scans.sh needs sqlite3 installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }
like() { case "$3" in $2) ok "$1" ;; *) bad "$1"; echo "      want: $2"; echo "      got:  $3" ;; esac; }

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
echo 1800000000 > "$F/clock"
printf '#!%s sh\nif [ "$*" = "+%%s" ]; then cat "%s/clock"; else exec "%s" date "$@"; fi\n' "$bb" "$F" "$bb" > "$t/bin/date"
printf '#!%s sh\necho $(( $(cat "%s/clock") + $1 )) > "%s/clock"\n' "$bb" "$F" "$F" > "$t/bin/sleep"
printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$F" > "$t/bin/logger"
cat > "$t/bin/nvram" <<'EOF'
#!/bin/sh
case "$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; wl0_ssid|wl1_ssid) echo HomeNet ;; esac
EOF
# Stand-in driver. Per interface, in $F: <ifc>.list (the figures it keeps: channel|obss|nocat|noise),
# <ifc>.cut (a full scan stops after this many channels), <ifc>.reject_rest (refuses `scan -c`),
# <ifc>.noop_rest (accepts `scan -c` but reaches nothing), <ifc>.stuck (a channel whose figures don't
# change), <ifc>.nolist (no per-channel figures), <ifc>.nets (channel bssid ssid), <ifc>.scans (log).
cat > "$t/bin/wl" <<'EOF'
#!@BB@ sh
F=@F@; ifc=$2; cmd=$3
all() { if [ "$ifc" = eth6 ]; then echo "1 2 3 4 5 6 7 8 9 10 11 12 13"; else echo "36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140"; fi; }
visit() {   # the scan reaches these channels: new figures for each, and what it heard there
	n=$(cat "$F/$ifc.n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$F/$ifc.n"
	: > "$F/$ifc.heard"; touch "$F/$ifc.list"
	for c in "$@"; do
		echo "$c" >> "$F/$ifc.heard"
		if [ -f "$F/$ifc.stuck" ] && [ "$(cat "$F/$ifc.stuck")" = "$c" ] && grep -q "^$c|" "$F/$ifc.list"; then continue; fi
		grep -v "^$c|" "$F/$ifc.list" > "$F/$ifc.tmp" || true; mv "$F/$ifc.tmp" "$F/$ifc.list"
		echo "$c|$(( (n * 3 + c) % 17 ))|$(( n % 5 ))|-$(( 88 + n % 4 ))" >> "$F/$ifc.list"
	done
}
case "$cmd" in
	isup) echo 1 ;;
	chanspec) if [ "$ifc" = eth6 ]; then echo "1 (0x1001)"; else echo "100l (0xd866)"; fi ;;
	channels) all ;;
	scan)
		if [ "$4" = -c ]; then
			echo "$5" >> "$F/$ifc.scans"
			if [ -f "$F/$ifc.reject_rest" ]; then echo "wl: Scan Rejected" >&2; exit 1; fi
			if [ -f "$F/$ifc.noop_rest" ]; then : > "$F/$ifc.heard"; exit 0; fi
			visit $(echo "$5" | tr ',' ' ')
		else
			echo full >> "$F/$ifc.scans"
			visit $(all | tr ' ' '\n' | head -n "$(cat "$F/$ifc.cut" 2>/dev/null || echo 99)")
		fi ;;
	scanresults)
		while read -r c b s; do
			if grep -qx "$c" "$F/$ifc.heard"; then printf 'SSID: "%s"\nMode: Managed\tRSSI: -60 dBm\tChannel: %s\nBSSID: %s\tCapability: ESS\n\n' "$s" "$c" "$b"; fi
		done < "$F/$ifc.nets" ;;
	chanim_stats)
		if [ "$4" != all ] || [ -f "$F/$ifc.nolist" ]; then exit 1; fi
		echo "version: 3"; echo "CHAN Interference Measurement:"; echo "Stats during last scan:"
		if [ "$ifc" = eth6 ]; then base=4096; else base=53248; fi
		sort -t'|' -k1,1n "$F/$ifc.list" 2>/dev/null | while IFS='|' read -r c o nc z; do
			printf ' chanspec: 0x%x crsglitch cnt: 0 bad plcp: 0 noise: %s\n\t cca_txdur: 1 cca_inbss: 0 cca_obss:%s cca_nocat: %s cca_nopkt: 0\n' $((c + base)) "$z" "$o" "$nc"
		done ;;
	*) exit 1 ;;
esac
EOF
sed -i "s|@BB@|$bb|; s|@F@|\"$F\"|" "$t/bin/wl"
printf '6 02:00:00:00:24:01 Near6\n' > "$F/eth6.nets"
printf '36 02:00:00:00:05:01 Near36\n124 02:00:00:00:05:02 Far124\n' > "$F/eth7.nets"
chmod +x "$t/bin/date" "$t/bin/sleep" "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl"
awk '/^init_db\(\) \{/ { f = 1 } f && /^EOF$/ { exit } f && p { print } f && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
"$sqlite" "$D/wifiinsight.db" < "$t/schema.sql"
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@"; }
q() { "$sqlite" "$D/wifiinsight.db" "$1"; }
scan() {   # run a scan, half an hour after the last; sets r2/r5 (each band's result) and ts (the 5 GHz scan's time)
	echo $(( $(cat "$F/clock") + 1800 )) > "$F/clock"
	out=$(run scan 2>&1) || true
	r2=$(printf '%s\n' "$out" | sed -n 's/^  2g (eth6): //p'); r5=$(printf '%s\n' "$out" | sed -n 's/^  5g (eth7): //p')
	ts=$(q "SELECT max(ts) FROM scans WHERE band='5g'")
}
measured() { q "SELECT count(*) FROM chanim WHERE band='5g' AND ts=$ts"; }
nets() { q "SELECT count(*) FROM aps WHERE band='5g' AND ts=$ts"; }
fig() { q "SELECT obss || ',' || nocat || ',' || noise FROM chanim WHERE band='5g' AND ts=$ts AND ch=$1"; }
calls() { tail -n +"$1" "$F/eth7.scans" | tr '\n' ' ' | sed 's/ $//'; }
REST=108,112,116,120,124,128,132,136,140

# 1: a full scan, the first since a reboot: every channel is new
scan
expect "full scan: 5 GHz" "ok, 2 networks in 3 s, 19 channels measured" "$r5"
expect "full scan: 2.4 GHz" "ok, 1 network in 3 s, 13 channels measured" "$r2"
expect "full scan: no follow-up" "full" "$(calls 1)"

# 2: the driver stops at 104 (a busy channel). The rest is scanned, and what it hears there counts.
# Channel 52's figures happen not to change: it's before 104, so it was reached and still counts.
echo 10 > "$F/eth7.cut"; echo 52 > "$F/eth7.stuck"; n=$(wc -l < "$F/eth7.scans")
scan
like "stopped at 104: finished with a second scan" "ok, 2 networks in * s, stopped at 104 and finished with a second scan, 19 channels measured" "$r5"
expect "stopped at 104: the follow-up asked for 108-140" "full $REST" "$(calls $((n + 1)))"
expect "stopped at 104: every channel measured, both networks kept" "19|2" "$(measured)|$(nets)"
expect "stopped at 104: 124 has the follow-up's figures (3rd visit), not the first scan's" "14,3,-91" "$(fig 124)"
expect "stopped at 104: 36 has this scan's figures (2nd visit)" "8,2,-90" "$(fig 36)"
expect "stopped at 104: 52 (same figures, before 104) counts" "1" "$(q "SELECT count(*) FROM chanim WHERE band='5g' AND ts=$ts AND ch=52")"
expect "stopped at 104: 2.4 GHz unaffected" "ok, 1 network in 3 s, 13 channels measured" "$r2"
rm -f "$F/eth7.stuck"

# 3: the follow-up is refused: only what the scan reached is stored, not 108-140's old figures
touch "$F/eth7.reject_rest"
scan
expect "follow-up refused: 10 channels, not the 19 the driver lists" "ok, 1 network in 3 s, 10 channels measured" "$r5"
expect "follow-up refused: no rows for 108-140" "10|0" "$(measured)|$(q "SELECT count(*) FROM chanim WHERE band='5g' AND ts=$ts AND ch>=108")"
rm -f "$F/eth7.reject_rest"

# 4: a follow-up that reaches nothing isn't repeated for the same channels (until a reboot)
touch "$F/eth7.noop_rest"; n=$(wc -l < "$F/eth7.scans")
scan
expect "follow-up reached nothing: tried once" "full $REST" "$(calls $((n + 1)))"
expect "follow-up reached nothing: 10 channels" "ok, 1 network in 3 s, 10 channels measured" "$r5"
n=$(wc -l < "$F/eth7.scans")
scan
expect "...and not tried again" "full" "$(calls $((n + 1)))"
rm -f "$F/eth7.noop_rest" "$R/tmp/wifiinsight/rest_5g.skip"

# 5: a driver without per-channel figures: no way to tell what was reached, so no follow-up
touch "$F/eth7.nolist"; n=$(wc -l < "$F/eth7.scans")
scan
expect "no per-channel figures: the scan as before" "ok, 1 network in 3 s" "$r5"
expect "no per-channel figures: no follow-up" "full" "$(calls $((n + 1)))"
rm -f "$F/eth7.nolist"

# 6: back to a full scan: no follow-up, every channel measured
rm -f "$F/eth7.cut"; n=$(wc -l < "$F/eth7.scans")
scan
expect "full scan again" "ok, 2 networks in 3 s, 19 channels measured" "$r5"
expect "full scan again: no follow-up" "full" "$(calls $((n + 1)))"
grep -q 'scan 5g (eth7): ok, 2 networks in .* s, stopped at 104 and finished with a second scan, 19 channels measured' "$F/log" && ok "syslog says when a scan was finished" || bad "syslog line for the finished scan"

[ $fail -eq 0 ] && echo "Short scans: all checks passed." || { echo "::error::Short scans: some checks failed."; exit 1; }
