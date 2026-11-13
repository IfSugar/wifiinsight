#!/bin/bash
# Regression test: routers with two radios on one band, or four radios, keep each radio apart.
#
# Layouts from the Asuswrt-Merlin source (rc/init.c wl_ifnames, shared/defaults.c wlN_nband):
#   GT-AXE16000  wl0 5 GHz-1 (eth7), wl1 5 GHz-2 (eth8), wl2 6 GHz (eth9), wl3 2.4 GHz (eth10)
#   GT-BE98 Pro  wl0 5 GHz, wl1 6 GHz-1, wl2 6 GHz-2, wl3 2.4 GHz (interfaces wl0-wl3)
#   GT-AX11000, GT-AX11000 Pro, XT12: wl0 2.4 GHz, wl1 5 GHz-1, wl2 5 GHz-2
# Up to 1.3.0 only wl0-wl2 were read, so a quad-band router's 2.4 GHz radio (wl3) was never seen, and
# history was kept per band, so two 5 GHz (or 6 GHz) radios wrote over each other. Now the first radio
# on a band keeps its key (2g, 5g, 6g) and the second is 5g2 or 6g2, named 5 GHz-1 and 5 GHz-2 as the
# router's own pages do. Also: the Wi-Fi 7 driver's 320 MHz chanspecs (0x3000 width bits on 6 GHz,
# centre in 160 MHz steps from channel 31) were read as 160 MHz around the wrong centre.
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs, on a fake clock.
# Usage: .github/tests/multi-radio.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, python3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::multi-radio.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::multi-radio.sh needs sqlite3 installed"; exit 1; }
bash_bin=$(command -v bash)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }

mkdir -p "$T/bin"
"$bb" --list > "$T/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$T/bb.list"; then ln -s "$bb" "$T/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$T/bin/$a"
	fi
done
rm -f "$T/bin/date" "$T/bin/sleep" "$T/bin/logger"
echo 'enable -n test [ printf echo' > "$T/no-builtins.sh"

# One router per call: a fresh install, data folder and stand-ins. The layout lines are
# "unit ifc nband chanspec hex channels" (nband - for none: then the chanspec says the band).
router() {   # name, layout lines
	t=$T/$1; shift; R=$t/root; F=$t/fix; D=$t/data
	mkdir -p "$R/jffs/addons/wifiinsight" "$R/www/user" "$R/tmp" "$F" "$D"
	cp "$script" "$R/jffs/addons/wifiinsight/wifiinsight.sh"
	printf 'SQLITE="%s"\nDATA_DIR="%s"\n' "$sqlite" "$D" > "$R/jffs/addons/wifiinsight/config"
	printf '%s\n' "$@" > "$F/radios"
	echo 1800000000 > "$F/clock"
	B=$t/bin; mkdir -p "$B"
	printf '#!%s sh\nif [ "$*" = "+%%s" ]; then cat "%s/clock"; else exec "%s" date "$@"; fi\n' "$bb" "$F" "$bb" > "$B/date"
	printf '#!%s sh\necho $(( $(cat "%s/clock") + $1 )) > "%s/clock"\n' "$bb" "$F" "$F" > "$B/sleep"
	printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$F" > "$B/logger"
	cat > "$B/nvram" <<EOF
#!$bb sh
F="$F"; k=\$2
case "\$k" in
	ntp_ready) echo 1 ;;
	wl[0-9]_ifname) u=\${k#wl}; u=\${u%_ifname}; awk -v u="\$u" '\$1 == u { print \$2 }' "\$F/radios" ;;
	wl[0-9]_nband) u=\${k#wl}; u=\${u%_nband}; awk -v u="\$u" '\$1 == u && \$3 != "-" { print \$3 }' "\$F/radios" ;;
	wl[0-9]_ssid) echo HomeNet ;;
esac
EOF
	cat > "$B/wl" <<'WL'
#!@BB@ sh
F=@F@; ifc=$2; cmd=$3; a4=${4:-}; a5=${5:-}; now=$(cat "$F/clock")
line=$(awk -v i="$ifc" '$2 == i' "$F/radios"); [ -n "$line" ] || { echo "wl: wl driver adapter not found" >&2; exit 1; }
set -- $line; cs=$4; hex=$5; shift 5; chs="$*"
case $(( hex & 0xc000 )) in 0) base=4096 ;; 16384) base=20480 ;; *) base=53248 ;; esac
visit() {
	n=$(cat "$F/$ifc.n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$F/$ifc.n"
	: > "$F/$ifc.heard"; touch "$F/$ifc.list"
	for c in "$@"; do
		echo "$c" >> "$F/$ifc.heard"
		grep -v "^$c|" "$F/$ifc.list" > "$F/$ifc.tmp" || true; mv "$F/$ifc.tmp" "$F/$ifc.list"
		echo "$c|$(( (n * 3 + c) % 17 ))|$(( n % 5 ))|-$(( 88 + n % 4 ))" >> "$F/$ifc.list"
	done
}
case "$cmd" in
	isup) echo 1 ;;
	chanspec) echo "$cs ($hex)" ;;
	channels) echo "$chs" ;;
	noise) echo -92 ;;
	scan)
		if [ "$a4" = -c ]; then echo "$a5" >> "$F/$ifc.scans"; visit $(echo "$a5" | tr ',' ' ')
		else
			if [ -f "$F/$ifc.reject_full" ]; then echo "wl: Scan Rejected" >&2; exit 1; fi
			echo full >> "$F/$ifc.scans"; visit $chs
		fi ;;
	scanresults)
		touch "$F/$ifc.heard" "$F/$ifc.nets"
		while read -r c b s; do
			if grep -qx "$c" "$F/$ifc.heard"; then printf 'SSID: "%s"\nMode: Managed\tRSSI: -60 dBm\tChannel: %s\nBSSID: %s\tCapability: ESS\n\n' "$s" "$c" "$b"; fi
		done < "$F/$ifc.nets" ;;
	chanim_stats)
		if [ "$a4" = all ]; then
			echo "version: 3"; echo "CHAN Interference Measurement:"; echo "Stats during last scan:"
			sort -t'|' -k1,1n "$F/$ifc.list" 2>/dev/null | while IFS='|' read -r c o nc z; do
				printf ' chanspec: 0x%x crsglitch cnt: 0 bad plcp: 0 noise: %s\n\t cca_txdur: 1 cca_inbss: 0 cca_obss:%s cca_nocat: %s cca_nopkt: 0\n' $((c + base)) "$z" "$o" "$nc"
			done
		else
			printf 'version: 4\nchspec tx inbss obss nocat nopkt doze txop goodtx badtx glitch badplcp knoise idle busy timestamps\n'
			printf '%s 1 0 4 1 1 0 96 0 0 1 0 -92 90 4 %s\n' "$cs" "$now"
		fi ;;
	*) exit 1 ;;
esac
WL
	sed -i "s|@BB@|$bb|; s|@F@|\"$F\"|" "$B/wl"
	chmod +x "$B/date" "$B/sleep" "$B/logger" "$B/nvram" "$B/wl"
	for f in "$T/bin"/*; do [ -e "$B/${f##*/}" ] || ln -s "$(readlink "$f")" "$B/${f##*/}"; done
	awk '/^init_db\(\) \{/ { f = 1 } f && /^EOF$/ { exit } f && p { print } f && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
	"$sqlite" "$D/wifiinsight.db" < "$t/schema.sql"
}
run() { WI_ROOT="$R" TZ=UTC PATH="$B" BASH_ENV="$T/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@"; }
q() { "$sqlite" "$D/wifiinsight.db" "$1"; }
later() { echo $(( $(cat "$F/clock") + ${1:-60} )) > "$F/clock"; }
samples() { q "SELECT band || ' ' || width || ' ' || center FROM samples WHERE ts=(SELECT max(ts) FROM samples) ORDER BY band" | tr '\n' ',' | sed 's/,$//'; }
radios_live() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(",".join("%s=%s %s" % (r["band"], r["name"], r["iface"]) for r in d["radios"]))' "$R/www/user/wifiinsight/live.htm"; }
scanned() { q "SELECT band || ':' || group_concat(ch, ' ') FROM (SELECT DISTINCT band, ch FROM scans ORDER BY band, ch) GROUP BY band ORDER BY band" | tr '\n' ',' | sed 's/,$//'; }
heard() { q "SELECT band || ':' || group_concat(ssid, ' ') FROM (SELECT DISTINCT band, ssid FROM aps ORDER BY band, ssid) GROUP BY band ORDER BY band" | tr '\n' ',' | sed 's/,$//'; }
results() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(",".join("%s=%s" % (k, v) for k, v in sorted(d["bands"].items())))' "$R/www/user/wifiinsight/scanstate.htm"; }
check_lines() { run check 2>&1 | grep -E 'GHz|radio' | sed 's/^ *//' | tr '\n' ';' | sed 's/;$//'; }

# 1: GT-AXE16000: 5 GHz-1, 5 GHz-2, 6 GHz, and 2.4 GHz on wl3
router axe16000 "0 eth7 1 36/80 0xe02a 36 40 44 48 52 56 60 64" "1 eth8 1 100/80 0xe06a 100 104 108 112 116 120 124 128 132 136 140" \
	"2 eth9 4 6g37/160 0x692f 1 5 9 13 17 21 25 29 33 37 41 45" "3 eth10 2 6 0x1006 1 2 3 4 5 6 7 8 9 10 11 12 13"
printf '36 02:00:00:00:05:01 Near36\n' > "$F/eth7.nets"; printf '124 02:00:00:00:05:02 Far124\n' > "$F/eth8.nets"
printf '37 02:00:00:00:06:01 Six37\n' > "$F/eth9.nets"; printf '6 02:00:00:00:24:01 Near6\n' > "$F/eth10.nets"
expect "GT-AXE16000: the check passes every radio, named as the router does" \
	"[ OK ] 5 GHz-1 (eth7) airtime statistics;[ OK ] 5 GHz-2 (eth8) airtime statistics;[ OK ] 6 GHz (eth9) airtime statistics;[ OK ] 2.4 GHz (eth10) airtime statistics" "$(check_lines)"
run collect --once > /dev/null 2>&1 || true
expect "GT-AXE16000: a sample from each radio, 2.4 GHz on wl3 included" "2g 20 6,5g 80 42,5g2 80 106,6g 160 47" "$(samples)"
expect "GT-AXE16000: the page gets each radio's name" "5g=5 GHz-1 eth7,5g2=5 GHz-2 eth8,6g=6 GHz eth9,2g=2.4 GHz eth10" "$(radios_live)"
expect "GT-AXE16000: monitoring starts once per radio" "2g,5g,5g2,6g" "$(q "SELECT group_concat(band) FROM (SELECT band FROM events WHERE tag='initial' ORDER BY band)")"
later 1800; run scan > /dev/null 2>&1 || true
expect "GT-AXE16000: each radio scans its own channels" \
	"2g:1 2 3 4 5 6 7 8 9 10 11 12 13,5g:36 40 44 48 52 56 60 64,5g2:100 104 108 112 116 120 124 128 132 136 140,6g:1 5 9 13 17 21 25 29 33 37 41 45" "$(scanned)"
expect "GT-AXE16000: and keeps what it heard" "2g:Near6,5g:Near36,5g2:Far124,6g:Six37" "$(heard)"
expect "GT-AXE16000: a result per radio" "2g=ok,5g=ok,5g2=ok,6g=ok" "$(results)"
expect "GT-AXE16000: measured channels per radio" "13 8 11 12" "$(cat "$D/measured_2g" "$D/measured_5g" "$D/measured_5g2" "$D/measured_6g" | tr '\n' ' ' | sed 's/ $//')"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); sys.exit(0 if sorted(d["aps"]) == ["2g", "5g", "5g2", "6g"] and sorted(d["scans"]) == ["2g", "5g", "5g2", "6g"] else 1)' "$R/www/user/wifiinsight/scans.htm" \
	&& ok "GT-AXE16000: scans.htm keeps the radios apart" || bad "GT-AXE16000: scans.htm keys"
# full scans refused on 5 GHz-2 only: only it goes one channel at a time
touch "$F/eth8.reject_full"; later 1800; out=$(run scan 2>&1) || true
case "$(printf '%s\n' "$out" | grep '^  5g2 (eth8): ')" in *"one channel at a time"*) ok "GT-AXE16000: 5 GHz-2 refused: one channel at a time" ;; *) bad "GT-AXE16000: 5g2 line"; printf '%s\n' "$out" | sed 's/^/      | /' ;; esac
expect "GT-AXE16000: the refusal is 5 GHz-2's alone" "refused_5g2" "$(cd "$R/tmp/wifiinsight" && ls refused_* 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
expect "GT-AXE16000: 5 GHz-1 still scans in full" "full" "$(tail -1 "$F/eth7.scans")"

# 2: GT-BE98 Pro: 5 GHz, 6 GHz-1 and 6 GHz-2 at 320 MHz, 2.4 GHz on wl3; and no wlN_nband: the chanspec says
router be98pro "0 wl0 - 36/160 0xe832 36 40 44 48 52 56 60 64" "1 wl1 - 6g37/320-1 0x7240 1 5 9 13 17 21 25 29 33 37 41 45 49 53 57 61" \
	"2 wl2 - 6g133/320-1 0x7044 129 133 137 141 145 149 153 157 161 165 169 173 177 181 185 189" "3 wl3 - 11 0x100b 1 2 3 4 5 6 7 8 9 10 11 12 13"
expect "GT-BE98 Pro: the check passes every radio" \
	"[ OK ] 5 GHz (wl0) airtime statistics;[ OK ] 6 GHz-1 (wl1) airtime statistics;[ OK ] 6 GHz-2 (wl2) airtime statistics;[ OK ] 2.4 GHz (wl3) airtime statistics" "$(check_lines)"
run collect --once > /dev/null 2>&1 || true
expect "GT-BE98 Pro: 320 MHz read as 320, around the right centre" "2g 20 11,5g 160 50,6g 320 31,6g2 320 159" "$(samples)"
expect "GT-BE98 Pro: names" "5g=5 GHz wl0,6g=6 GHz-1 wl1,6g2=6 GHz-2 wl2,2g=2.4 GHz wl3" "$(radios_live)"

# 3: GT-AX11000: 2.4 GHz, 5 GHz-1, 5 GHz-2
router ax11000 "0 eth6 2 6 0x1006 1 2 3 4 5 6 7 8 9 10 11 12 13" "1 eth7 1 36/80 0xe02a 36 40 44 48 52 56 60 64" "2 eth8 1 149/80 0xe09b 100 104 108 112 116 120 124 128 132 136 140 149 153 157 161 165"
run collect --once > /dev/null 2>&1 || true
expect "GT-AX11000: names" "2g=2.4 GHz eth6,5g=5 GHz-1 eth7,5g2=5 GHz-2 eth8" "$(radios_live)"

# 4: a dual-band router is as before: 2g and 5g, plain names
router ax86u "0 eth6 2 6 0x1006 1 2 3 4 5 6 7 8 9 10 11 12 13" "1 eth7 1 44/80 0xe02a 36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140"
run collect --once > /dev/null 2>&1 || true
expect "RT-AX86U: keys and names as before" "2g=2.4 GHz eth6,5g=5 GHz eth7" "$(radios_live)"
expect "RT-AX86U: samples as before" "2g 20 6,5g 80 42" "$(samples)"

[ $fail -eq 0 ] && echo "Multi-radio: all checks passed." || { echo "::error::Multi-radio: some checks failed."; exit 1; }
