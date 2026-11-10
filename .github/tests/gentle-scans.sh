#!/bin/bash
# Regression test: neighbour scans go a few channels at a time, and only what they measure is stored.
#
# A whole-band scan kept the radio off its channel long enough for apps on an iPhone to stall for
# 20-30 s, and on a busy channel the driver could stop it partway (an RT-AX86U stopped at 104 of
# 36-140). WiFi Insight now scans two channels at a time on 5 GHz (four on 2.4 GHz) with a pause
# back on the router's channel in between:
#  - every channel is scanned, in groups, and never the whole band at once;
#  - the driver keeps each channel's last figures, so only channels whose figures changed (or that
#    come before one that did, in the group) are stored: a refused group's old figures aren't;
#  - a refused group is retried for 20 s, then skipped and reported; all refused: "busy".
#
# A stand-in driver keeps per-channel figures between scans and updates only the channels it visits.
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs, on a fake clock.
# Usage: .github/tests/gentle-scans.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::gentle-scans.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::gentle-scans.sh needs sqlite3 installed"; exit 1; }
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
# <ifc>.reject (a channel list it refuses, or "all"), <ifc>.stuck (a channel whose figures don't change),
# <ifc>.nolist (no per-channel figures), <ifc>.nets (channel bssid ssid), <ifc>.scans (each scan's channels).
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
			r=$(cat "$F/$ifc.reject" 2>/dev/null || true)
			if [ "$r" = all ] || [ "$r" = "$5" ]; then echo "wl: Scan Rejected" >&2; exit 1; fi
			visit $(echo "$5" | tr ',' ' ')
		else
			echo full >> "$F/$ifc.scans"; visit $(all)
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
G5="36,40 44,48 52,56 60,64 100,104 108,112 116,120 124,128 132,136 140"; G2="1,2,3,4 5,6,7,8 9,10,11,12 13"
calls2() { tail -n +"$1" "$F/eth6.scans" | tr '\n' ' ' | sed 's/ $//'; }
uniq_calls() { sort "$F/eth7.scans" | uniq -d | wc -l | tr -d ' '; }

# 1: the first scan since a reboot: every group once, never the whole band; every channel measured
scan
expect "5 GHz: two channels at a time" "$G5" "$(calls 1)"
expect "2.4 GHz: four at a time" "$G2" "$(calls2 1)"
like "5 GHz: every channel measured" "ok, 2 networks in * s, 19 channels measured" "$r5"
like "2.4 GHz: every channel measured" "ok, 1 network in * s, 13 channels measured" "$r2"
expect "networks from every group (36 and 124)" "2" "$(nets)"

# 2: the next scan: this scan's figures (2nd visit), for every channel
n=$(wc -l < "$F/eth7.scans")
scan
expect "next scan: the same groups" "$G5" "$(calls $((n + 1)))"
# (the stand-in counts every group it scans: 36 is its 11th visit and 124 its 18th)
expect "next scan: 19 channels, this scan's figures" "19|1,1,-91|8,3,-90" "$(measured)|$(fig 36)|$(fig 124)"

# 3: a group the radio refuses: retried for 20 s, then skipped. Its channels keep their old figures in
# the driver's list, and those aren't stored for this scan; nor is the network only heard there.
echo 124,128 > "$F/eth7.reject"
scan
like "refused group: reported" "ok, 1 network in * s, 1 of 10 channel groups not scanned (wl said \"Scan Rejected\" for 2? s), 17 channels measured" "$r5"
expect "refused group: no rows for 124 and 128, the rest stored" "17|0|1" "$(measured)|$(q "SELECT count(*) FROM chanim WHERE band='5g' AND ts=$ts AND ch IN (124, 128)")|$(nets)"
rm -f "$F/eth7.reject"

# 4: a channel whose figures happen not to change: it comes before one that did, so it was measured
echo 124 > "$F/eth7.stuck"
scan
like "unchanged figures before a changed channel still count" "ok, 2 networks in * s, 19 channels measured" "$r5"
rm -f "$F/eth7.stuck"

# 5: a driver without per-channel figures: networks from every group, no measurements
touch "$F/eth7.nolist"
scan
like "no per-channel figures: networks only" "ok, 2 networks in * s" "$r5"
case "$r5" in *measured*) bad "no per-channel figures: nothing measured" ;; *) ok "no per-channel figures: nothing measured" ;; esac
rm -f "$F/eth7.nolist"

# 6: every group refused: busy, and the previous scan stays
echo all > "$F/eth7.reject"; before=$ts
scan
like "every group refused: busy" "busy, wl said \"Scan Rejected\" for 2? s" "$r5"
expect "every group refused: no new 5 GHz scan stored" "$before" "$ts"
rm -f "$F/eth7.reject"

expect "never a whole-band scan" "0" "$(grep -c '^full$' "$F/eth7.scans" "$F/eth6.scans" | awk -F: '{ s += $2 } END { print s }')"
grep -q 'scan 5g (eth7): ok, 2 networks in .* s, 19 channels measured' "$F/log" && ok "syslog lines" || bad "syslog lines"

[ $fail -eq 0 ] && echo "Gentle scans: all checks passed." || { echo "::error::Gentle scans: some checks failed."; exit 1; }
