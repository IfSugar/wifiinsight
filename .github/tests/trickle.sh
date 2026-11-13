#!/bin/bash
# Regression test: one-channel scans spread over time, only as a fallback.
#
# Where the driver refuses full scans (some do on a DFS channel), 1.3.0 scanned the band one channel at a
# time in a burst of up to 150 s at every scheduled scan. Now that's spread out: a full scan is always
# tried first, and the first refusal still gets the burst; after that, each scheduled scan starts a sweep
# that 'trickle' (cron, every minute) carries on: a third of the scan interval for the band (2 channels a
# minute for 19 channels at 30-minute scans, one every 2 minutes at 2-hour scans), then a rest until the
# next scheduled scan. It skips while the router's own traffic is high (but not for longer than the scan
# interval), and scheduled scans only retry the full scan every 6 hours. A sweep of the band is one scan
# whose time moves forward with each channel. Routers whose full scans work never trickle.
#
# Same stand-in driver as one-channel.sh. Runs with Merlin's BusyBox commands only, and [, printf and
# echo as separate programs, on a fake clock.
# Usage: .github/tests/trickle.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, python3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::trickle.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::trickle.sh needs sqlite3 installed"; exit 1; }
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
# <ifc>.reject_full (refuses full scans), <ifc>.every (takes a single channel at most once every N
# seconds), <ifc>.never (refuses single channels too), <ifc>.bad (a channel it calls "Bad Channel"),
# <ifc>.stuck (a channel whose figures never change), <ifc>.nets (channel bssid ssid), <ifc>.scans (log of
# accepted scans), <ifc>.tries (one line per full-scan request).
cat > "$t/bin/wl" <<'WL'
#!@BB@ sh
F=@F@; ifc=$2; cmd=$3; now=$(cat "$F/clock")
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
	isup) if [ -f "$F/$ifc.down" ]; then echo 0; else echo 1; fi ;;
	chanspec) if [ "$ifc" = eth6 ]; then echo "1 (0x1001)"; else echo "100/160 (0xe872)"; fi ;;
	channels) all ;;
	scan)
		if [ "$4" = -c ]; then
			if [ -f "$F/$ifc.bad" ] && [ "$(cat "$F/$ifc.bad")" = "$5" ]; then echo "wl: Bad Channel" >&2; exit 1; fi
			if [ -f "$F/$ifc.never" ]; then echo "wl: Scan Rejected" >&2; exit 1; fi
			if [ -f "$F/$ifc.every" ] && [ "$now" -lt $(( $(cat "$F/$ifc.lastok" 2>/dev/null || echo 0) + $(cat "$F/$ifc.every") )) ]; then
				echo "wl: Scan Rejected" >&2; exit 1
			fi
			echo "$now" > "$F/$ifc.lastok"; echo "$5" >> "$F/$ifc.scans"
			visit $(echo "$5" | tr ',' ' ')
		else
			echo full >> "$F/$ifc.tries"
			if [ -f "$F/$ifc.reject_full" ]; then echo "wl: Scan Rejected" >&2; exit 1; fi
			echo full >> "$F/$ifc.scans"; visit $(all)
		fi ;;
	scanresults)
		touch "$F/$ifc.heard"
		while read -r c b s; do
			if grep -qx "$c" "$F/$ifc.heard"; then printf 'SSID: "%s"\nMode: Managed\tRSSI: -60 dBm\tChannel: %s\nBSSID: %s\tCapability: ESS\n\n' "$s" "$c" "$b"; fi
		done < "$F/$ifc.nets" ;;
	chanim_stats)
		[ "$4" = all ] || exit 1
		echo "version: 3"; echo "CHAN Interference Measurement:"; echo "Stats during last scan:"
		if [ "$ifc" = eth6 ]; then base=4096; else base=53248; fi
		sort -t'|' -k1,1n "$F/$ifc.list" 2>/dev/null | while IFS='|' read -r c o nc z; do
			printf ' chanspec: 0x%x crsglitch cnt: 0 bad plcp: 0 noise: %s\n\t cca_txdur: 1 cca_inbss: 0 cca_obss:%s cca_nocat: %s cca_nopkt: 0\n' $((c + base)) "$z" "$o" "$nc"
		done ;;
	*) exit 1 ;;
esac
WL
sed -i "s|@BB@|$bb|; s|@F@|\"$F\"|" "$t/bin/wl"
printf '6 02:00:00:00:24:01 Near6\n' > "$F/eth6.nets"
printf '36 02:00:00:00:05:01 Near36\n124 02:00:00:00:05:02 Far124\n' > "$F/eth7.nets"
chmod +x "$t/bin/date" "$t/bin/sleep" "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl"
awk '/^SCHEMA=\047/ { f = 1; sub(/^SCHEMA=\047/, "") } f { e = ($0 ~ /\047$/); if (e) sub(/\047$/, ""); print; if (e) exit; next } /^init_db\(\) \{/ { h = 1 } h && /^EOF$/ { exit } h && p { print } h && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
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
mark() { touch "$F/eth7.scans"; wc -l < "$F/eth7.scans" | tr -d ' '; }
calls() { tail -n +"$1" "$F/eth7.scans" | tr '\n' ' ' | sed 's/ $//'; }
tries() { touch "$F/eth7.tries"; wc -l < "$F/eth7.tries" | tr -d ' '; }
rows() { q "SELECT count(*) FROM scans WHERE band='5g' AND ts=$ts"; }
ALL="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140"
FIRST='full scan refused: wl said "Scan Rejected" for 20 s'
AGAIN='full scan refused: wl said "Scan Rejected" again'
from() { echo $ALL | awk -v s="$1" -v k="$2" '{ for (i = 1; i <= NF; i++) if ($i == s) break; o = ""; for (j = 0; j < k; j++) o = o (o == "" ? "" : " ") $((i - 1 + j) % NF + 1); print o }'; }
survey() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(" ".join(sorted("%s@%s" % (a["ssid"], "new" if a["ts"] == d["last_scan"]["5g"] else "old") for a in d["aps"]["5g"])))' "$R/www/user/wifiinsight/scans.htm"; }

sched() {   # a scheduled scan (cron's 'scan --delay'), half an hour after the last
	echo $(( $(cat "$F/clock") + 1800 )) > "$F/clock"
	out=$(run scan --delay 2>&1) || true
	r5=$(printf '%s\n' "$out" | sed -n 's/^  5g (eth7): //p'); ts=$(q "SELECT max(ts) FROM scans WHERE band='5g'")
}
step() {   # cron's 'trickle', a minute after the last
	echo $(( $(cat "$F/clock") + 60 )) > "$F/clock"
	run trickle > /dev/null 2>&1 || true
	ts=$(q "SELECT max(ts) FROM scans WHERE band='5g'")
}
sample() {   # a sample of the router's own channel now: own traffic (tx + inbss) in percent
	q "INSERT INTO samples(ts, band, obss, nocat, tx, inbss, idle, noise) VALUES($(cat "$F/clock"), '5g', 1, 1, $1, 0, 90, -90)"
}

# 1: full scans work: trickle never scans, nor takes the scan lock (a scheduled scan starting in the same
# second must never find it taken); the scheduled scan is a full one, and refreshes live.htm too
n=$(mark); rm -f "$R/tmp/wifiinsight/scan.lock"; step; step
expect "full scans work: trickle does nothing" "" "$(calls $((n + 1)))"
[ ! -e "$R/tmp/wifiinsight/scan.lock" ] && ok "full scans work: trickle doesn't even take the scan lock" || bad "trickle took the scan lock"
rm -f "$R/www/user/wifiinsight/live.htm"
sched
expect "full scans work: a full scheduled scan" "ok, 2 networks in 3 s, 19 channels measured" "$r5"
[ -f "$R/www/user/wifiinsight/live.htm" ] && ok "a scan refreshes live.htm (the channel tile)" || bad "a scan left live.htm alone"

# 2: the first refusal: the scheduled scan still gets the whole band at once, one channel at a time
touch "$F/eth7.reject_full"; n=$(mark)
sched
like "first refusal: a burst, as before" "ok, 2 networks in * s, one channel at a time ($FIRST), 19 channels measured" "$r5"
expect "first refusal: every channel" "$ALL" "$(calls $((n + 1)))"
n=$(mark); step; step
expect "first refusal: trickle waits for the next scheduled scan" "" "$(calls $((n + 1)))"

# 3: from then on, scheduled scans don't scan (nor retry the full scan) until 6 hours have passed
n=$(mark); f=$(tries); b=$(q "SELECT count(DISTINCT ts) FROM scans WHERE band='5g'")
sched
expect "spread: the scheduled scan says so" "ok, one channel at a time, spread out (full scans refused on this channel)" "$r5"
expect "spread: no full-scan try, no channel scanned, nothing stored" "0||$b" "$(( $(tries) - f ))|$(calls $((n + 1)))|$(q "SELECT count(DISTINCT ts) FROM scans WHERE band='5g'")"

# 4: trickle: 2 channels a minute (19 channels in about 10 minutes), in order, as one sweep whose time moves forward
n=$(mark); step; t1=$ts
expect "trickle: 2 channels a minute, from the start of the band" "36 40" "$(calls $((n + 1)))"
step; step
expect "trickle: in order" "36 40 44 48 52 56" "$(calls $((n + 1)))"
expect "trickle: one sweep, at the latest channel's time" "6|$(cat "$F/clock" | awk '{ print $1 - 1 }')" "$(rows)|$ts"
[ "$ts" -gt "$t1" ] && ok "trickle: the sweep moved forward" || bad "trickle: sweep time $t1 -> $ts"
expect "trickle: measured, and the networks it heard" "6|1" "$(measured)|$(nets)"
expect "trickle: Site Survey keeps Far124 from the burst" "Far124@old Near36@new" "$(survey)"

# 5: not twice in a minute
n=$(mark); run trickle > /dev/null 2>&1 || true
expect "trickle: nothing before it's due" "" "$(calls $((n + 1)))"

# 6: busy with your own traffic: wait, but not for longer than the scan interval (30 min)
n=$(mark); sample 35; step
expect "own traffic high: skipped" "" "$(calls $((n + 1)))"
i=0; while [ $i -lt 27 ]; do sample 35; step; i=$((i + 1)); done
expect "own traffic high for 28 min: still waiting" "" "$(calls $((n + 1)))"
sample 35; step; sample 35; step
expect "own traffic high for 30 min: scans anyway" "60 64" "$(calls $((n + 1)))"
sample 3; n=$(mark); step
expect "own traffic low again: the next ones" "100 104" "$(calls $((n + 1)))"

# 7: a refused single channel: the same one next time
touch "$F/eth7.never"; n=$(mark); step
rm -f "$F/eth7.never"; step
expect "refused: tried again" "108 112" "$(calls $((n + 1)))"

# 8: the rest of the band, then one line in the syslog, a rest, and a new sweep with the next scheduled scan
n=$(mark); step; step; step; step
expect "sweep: the rest of the band, stopping at its end" "116 120 124 128 132 136 140" "$(calls $((n + 1)))"
grep -q '^scan 5g (eth7): one channel at a time, spread out: 19 channels, 2 networks, 19 channels measured$' "$F/log" \
	&& ok "sweep done: logged" || { bad "sweep done: syslog"; tail -3 "$F/log"; }
full=$ts; n=$(mark); step; step
expect "sweep done: rests until the next scheduled scan" "" "$(calls $((n + 1)))"
sched; step
expect "sweep done: the next scheduled scan starts a new one" "36 40|2" "$(calls $((n + 1)))|$(rows)"
expect "sweep done: the finished one stays whole" "19" "$(q "SELECT count(*) FROM scans WHERE band='5g' AND ts=$full")"

# 8b: switched off: scheduled scans say so, and trickle leaves the radio alone
touch "$F/eth7.down"; n=$(mark); sched
expect "radio off: the scheduled scan says off" "off" "$r5"
step; step
expect "radio off: trickle doesn't scan it" "" "$(calls $((n + 1)))"
rm -f "$F/eth7.down"

# 9: another channel (the router moved, say): trickle stops, scheduled scans try a full scan again
echo "0xd02a $(cat "$F/clock")" > "$R/tmp/wifiinsight/refused_5g"; n=$(mark); step
expect "other chanspec: trickle does nothing" "" "$(calls $((n + 1)))"
echo "0xe872 $(cat "$F/clock")" > "$R/tmp/wifiinsight/refused_5g"

# 10: six hours on, the scheduled scan retries the full scan; it works now: back to full scans
rm -f "$F/eth7.reject_full"; echo $(( $(cat "$F/clock") + 6 * 3600 )) > "$F/clock"
sched
expect "full scans work again" "ok, 2 networks in 3 s, 19 channels measured" "$r5"
[ ! -f "$R/tmp/wifiinsight/refused_5g" ] && ok "full scans work again: the refusal is forgotten" || bad "refused_5g still there"
n=$(mark); step
expect "full scans work again: trickle stops" "" "$(calls $((n + 1)))"

# 11: 2-hour scans: one channel every 2 minutes (a sweep in about 40 minutes)
touch "$F/eth7.reject_full"; sched; sched   # refused again: the burst, then a sweep
echo 'SCAN_INTERVAL=120' >> "$R/jffs/addons/wifiinsight/config"
n=$(mark); step; step; step; step
expect "2-hour scans: one channel every 2 minutes" "36 40" "$(calls $((n + 1)))"
echo 44 > "$F/eth7.bad"; n=$(mark); step; step; step; step; rm -f "$F/eth7.bad"
expect "a channel radar put off limits: skipped" "48 52" "$(calls $((n + 1)))"

# 12: scans paused: no trickle
sed -i 's/^COLLECTION=.*//' "$R/jffs/addons/wifiinsight/config"; echo 'COLLECTION="paused"' >> "$R/jffs/addons/wifiinsight/config"
n=$(mark); step; step
expect "scans paused: no trickle" "" "$(calls $((n + 1)))"

[ $fail -eq 0 ] && echo "Spread-out scans: all checks passed." || { echo "::error::Spread-out scans: some checks failed."; exit 1; }
