#!/bin/bash
# Regression test: one channel at a time when the driver refuses a full scan.
#
# On a DFS channel, some drivers refuse every full 5 GHz scan ("Scan Rejected"): an RT-BE88U on 100/160
# took every single-channel scan instead, while an RT-AX88U on 52/80 and a GT-AX6000 on 100/80 took the
# odd one. WiFi Insight then scans the channels one by one: each retried for up to 10 s, "Bad Channel"
# (put off limits by radar) skipped at once, giving up after three refused in a row or 150 s, and the
# next scan starts where this one stopped.
#
# A stand-in driver keeps per-channel figures between scans, refuses full scans, and takes single
# channels always, at most one every N seconds, or never. Runs with Merlin's BusyBox commands only,
# and [, printf and echo as separate programs, on a fake clock.
# Usage: .github/tests/one-channel.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, python3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::one-channel.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::one-channel.sh needs sqlite3 installed"; exit 1; }
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
	isup) echo 1 ;;
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

# 1: full scans work: nothing changes
scan
expect "full scan: as before" "ok, 2 networks in 3 s, 19 channels measured" "$r5"
expect "full scan: every channel stored" "19" "$(rows)"

# 2: an RT-BE88U on a DFS channel: full scans refused, every single channel taken
touch "$F/eth7.reject_full"; n=$(mark); f=$(tries)
scan
like "full refused: one channel at a time" "ok, 2 networks in * s, one channel at a time ($FIRST), 19 channels measured" "$r5"
expect "full refused: each channel on its own, in order" "$ALL" "$(calls $((n + 1)))"
expect "full refused: every channel stored and measured, both networks kept" "19|19|2" "$(rows)|$(measured)|$(nets)"
expect "full refused: the full scan retried for 20 s" "11" "$(( $(tries) - f ))"
expect "full refused: 2.4 GHz unaffected" "ok, 1 network in 3 s, 13 channels measured" "$r2"
grep -q "^scan 5g (eth7): ok, 2 networks in .* s, one channel at a time ($FIRST), 19 channels measured" "$F/log" \
	&& ok "full refused: syslog says how" || bad "full refused: syslog line"
python3 - "$R/www/user/wifiinsight/scanstate.htm" <<'PY' && ok "full refused: the page sees ok" || bad "full refused: scanstate.htm"
import json, sys
s = json.load(open(sys.argv[1])); sys.exit(0 if s['bands']['5g'] == 'ok' and 'one channel at a time' in s['notes']['5g'] else 1)
PY

# 3: the refusal is remembered: the full scan is tried once, not for 20 s
f=$(tries)
scan
like "remembered: straight to one channel at a time" "ok, 2 networks in * s, one channel at a time ($AGAIN), 19 channels measured" "$r5"
expect "remembered: one full-scan try" "1" "$(( $(tries) - f ))"

# 4: radar put 52 off limits: skipped at once, the rest still scanned and stored, 52 not stored
echo 52 > "$F/eth7.bad"
scan
like "Bad Channel: skipped" "ok, 2 networks in * s, one channel at a time ($AGAIN), 18 of 19 channels (wl said \"Bad Channel\" for 0 s), 18 channels measured" "$r5"
expect "Bad Channel: 18 channels stored, 52 not" "18|0" "$(rows)|$(q "SELECT count(*) FROM scans WHERE band='5g' AND ts=$ts AND ch=52")"
rm -f "$F/eth7.bad"

# 5: a quiet channel can give the same figures twice: where a network was heard, it still counts
echo 124 > "$F/eth7.stuck"
scan
expect "same figures, network heard: still measured" "ok|19" "${r5%%,*}|$(measured)"
expect "same figures, network heard: 124 stored" "1" "$(q "SELECT count(*) FROM chanim WHERE band='5g' AND ts=$ts AND ch=124")"
rm -f "$F/eth7.stuck"

# 6: a GT-AX6000: one single channel every 16 s. Each channel waits its turn, so none is skipped; the band
# stops after 150 s, only the channels covered are stored, and the next scan starts where this one stopped.
echo 16 > "$F/eth7.every"; rm -f "$F/eth7.lastok" "$R/tmp/wifiinsight/each_5g.next"; n=$(mark)
scan
first=$(calls $((n + 1))); k=$(echo $first | wc -w | tr -d ' ')
[ "$k" -ge 6 ] && [ "$k" -lt 19 ] && ok "one every 16 s: $k channels in the 150 s" || bad "one every 16 s: $k channels"
expect "one every 16 s: consecutive, from the start of the band" "$(from 36 $k)" "$first"
like "one every 16 s: says how much" "ok, * in * s, one channel at a time ($AGAIN), $k of 19 channels*, the rest next time, $k channels measured" "$r5"
expect "one every 16 s: only the channels covered are stored" "$k" "$(rows)"
expect "one every 16 s: Site Survey keeps Far124 from the earlier scan" "Far124@old Near36@new" "$(survey)"
nextc=$(echo $ALL | cut -d' ' -f$((k + 1))); n=$(mark)
scan
second=$(calls $((n + 1))); k2=$(echo $second | wc -w | tr -d ' ')
expect "next scan: carries on where the last stopped, consecutive" "$(from $nextc $k2)" "$second"
rm -f "$F/eth7.every"

# 7: an RT-AX88U: one every 40 s, longer than the old 20 s wait: still none skipped
echo 40 > "$F/eth7.every"; rm -f "$F/eth7.lastok" "$R/tmp/wifiinsight/each_5g.next"; n=$(mark)
scan
first=$(calls $((n + 1))); k=$(echo $first | wc -w | tr -d ' ')
[ "$k" -ge 3 ] && ok "one every 40 s: $k channels" || bad "one every 40 s: $k channels"
expect "one every 40 s: consecutive" "$(from 36 $k)" "$first"
rm -f "$F/eth7.every"

# 8: single channels refused too: about a minute, then busy, and the last scan is kept
touch "$F/eth7.never"; n=$(mark); b=$(q "SELECT count(DISTINCT ts) FROM scans WHERE band='5g'"); c0=$(cat "$F/clock")
scan
expect "never: busy" "busy, wl said \"Scan Rejected\" again; single channels refused too" "$r5"
expect "never: no scan saved" "$b" "$(q "SELECT count(DISTINCT ts) FROM scans WHERE band='5g'")"
expect "never: nothing accepted" "" "$(calls $((n + 1)))"
el=$(( $(cat "$F/clock") - c0 - 1800 )); [ "$el" -le 75 ] && ok "never: gave up after about a minute ($el s)" || bad "never: took $el s"
rm -f "$F/eth7.never"

# 9: six hours later the full scan gets its 20 s again (still refused here)
echo $(( $(cat "$F/clock") + 6 * 3600 )) > "$F/clock"; f=$(tries)
scan
like "6 h later: the full scan retried for 20 s" "ok, * one channel at a time ($FIRST)*" "$r5"
expect "6 h later: 11 tries" "11" "$(( $(tries) - f ))"

# 10: full scans taken again: back to one full scan, and the refusal is forgotten
rm -f "$F/eth7.reject_full"; n=$(mark)
scan
expect "full scan again" "ok, 2 networks in 3 s, 19 channels measured" "$r5"
expect "full scan again: one call, every channel stored" "full|19" "$(calls $((n + 1)))|$(rows)"
[ ! -f "$R/tmp/wifiinsight/refused_5g" ] && ok "full scan again: refusal forgotten" || bad "full scan again: refused_5g still there"

[ $fail -eq 0 ] && echo "One channel at a time: all checks passed." || { echo "::error::One channel at a time: some checks failed."; exit 1; }
