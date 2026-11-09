#!/bin/bash
# Regression test: what the radio measures on each channel during a scan is stored and exported.
#
# After a scan, `wl chanim_stats all` lists each scanned channel's airtime: other networks (obss),
# non-Wi-Fi (nocat), undecodable energy (nopkt), glitches, bad frame headers and the noise floor.
#  1. The parser reads the 3004.388 layout (real output from an RT-AX86U, channel codes and numbers
#     only), a table layout, skips other bands and refuses a single row (the radio's own channel).
#  2. A scan stores the measurements with the scan's timestamp, scans.htm and month.htm carry them
#     next to the estimate, and prune removes old ones.
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs, on a fake
# clock (date +%s and sleep) so the scan's waits take no time.
# Usage: .github/tests/measured.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, python3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::measured.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::measured.sh needs sqlite3 installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }

# RT-AX86U, 3004.388.12_2, `wl -i eth7 chanim_stats all` after a scan (first 11 of 19 channels)
V3_5G='version: 3
CHAN Interference Measurement:
Stats during last scan:
 chanspec: 0xd024 crsglitch cnt: 0 bad plcp: 16 noise: -93
	 cca_txdur: 2 cca_inbss: 3 cca_obss:1 cca_nocat: 3 cca_nopkt: 1
 chanspec: 0xd028 crsglitch cnt: 0 bad plcp: 50 noise: -93
	 cca_txdur: 2 cca_inbss: 6 cca_obss:6 cca_nocat: 2 cca_nopkt: 1
 chanspec: 0xd02c crsglitch cnt: 0 bad plcp: 66 noise: -93
	 cca_txdur: 2 cca_inbss: 2 cca_obss:2 cca_nocat: 4 cca_nopkt: 1
 chanspec: 0xd030 crsglitch cnt: 0 bad plcp: 16 noise: -93
	 cca_txdur: 2 cca_inbss: 4 cca_obss:2 cca_nocat: 2 cca_nopkt: 1
 chanspec: 0xd034 crsglitch cnt: 0 bad plcp: 23 noise: -93
	 cca_txdur: 1 cca_inbss: 2 cca_obss:2 cca_nocat: 0 cca_nopkt: 1
 chanspec: 0xd038 crsglitch cnt: 0 bad plcp: 0 noise: -94
	 cca_txdur: 0 cca_inbss: 0 cca_obss:0 cca_nocat: 0 cca_nopkt: 0
 chanspec: 0xd03c crsglitch cnt: 22 bad plcp: 0 noise: -91
	 cca_txdur: 6 cca_inbss: 4 cca_obss:4 cca_nocat: 8 cca_nopkt: 1
 chanspec: 0xd040 crsglitch cnt: 0 bad plcp: 0 noise: -94
	 cca_txdur: 1 cca_inbss: 2 cca_obss:2 cca_nocat: 0 cca_nopkt: 0
 chanspec: 0xd064 crsglitch cnt: 0 bad plcp: 0 noise: -91
	 cca_txdur: 8 cca_inbss: 12 cca_obss:1 cca_nocat: 6 cca_nopkt: 0
 chanspec: 0xd068 crsglitch cnt: 0 bad plcp: 50 noise: -95
	 cca_txdur: 2 cca_inbss: 3 cca_obss:2 cca_nocat: 1 cca_nopkt: 1
 chanspec: 0xd06c crsglitch cnt: 0 bad plcp: 0 noise: -94
	 cca_txdur: 1 cca_inbss: 1 cca_obss:0 cca_nocat: 0 cca_nopkt: 0
'
V3_2G='version: 3
CHAN Interference Measurement:
Stats during last scan:
 chanspec: 0x1001 crsglitch cnt: 630 bad plcp: 76 noise: -86
	 cca_txdur: 6 cca_inbss: 1 cca_obss:11 cca_nocat: 1 cca_nopkt: 1
 chanspec: 0x1002 crsglitch cnt: 603 bad plcp: 113 noise: -82
	 cca_txdur: 8 cca_inbss: 19 cca_obss:0 cca_nocat: 6 cca_nopkt: 9
 chanspec: 0x1003 crsglitch cnt: 3700 bad plcp: 240 noise: -67
	 cca_txdur: 7 cca_inbss: 0 cca_obss:0 cca_nocat: 16 cca_nopkt: 16
'
HDR='chspec tx inbss obss nocat nopkt doze txop goodtx badtx glitch badplcp knoise idle busy timestamps'

# ---- 1: the parser, with BusyBox awk -------------------------------------------------------------
mkdir -p "$t/awkbin"; ln -s "$bb" "$t/awkbin/awk"
sed -n '/^parse_chanim_all() {/,/^}/p' "$script" > "$t/p.sh"
grep -q '^parse_chanim_all() {' "$t/p.sh" || { echo "::error::no parse_chanim_all in the script"; exit 1; }
parse() { printf '%s' "$3" | PATH="$t/awkbin:$PATH" "$bb" ash -c '. "$1"; parse_chanim_all "$2" "$3"' sh "$t/p.sh" "$1" "$2"; }
rows() { grep '^INSERT' | sed "s/^INSERT OR REPLACE INTO chanim VALUES(//; s/);\$//"; }

out=$(parse 1800000000 5g "$V3_5G" | rows)
expect "3004.388 layout, 5 GHz: one row per channel" "11" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
expect "3004.388 layout, 5 GHz: channel 36 (ts, band, ch, others, non-Wi-Fi, unclassified, glitches, bad PLCP, noise)" \
	"1800000000,'5g',36,1,3,1,0,16,-93" "$(printf '%s\n' "$out" | head -1)"
expect "3004.388 layout, 5 GHz: channel 60" "1800000000,'5g',60,4,8,1,22,0,-91" "$(printf '%s\n' "$out" | grep ",60,")"
expect "3004.388 layout, 5 GHz: channels" "36 40 44 48 52 56 60 64 100 104 108" "$(printf '%s\n' "$out" | cut -d, -f3 | tr '\n' ' ' | sed 's/ $//')"
expect "3004.388 layout, 2.4 GHz" "1800000000,'2g',3,0,16,16,3700,240,-67" "$(parse 1800000000 2g "$V3_2G" | rows | grep ",3,0,")"
expect "channels of another band are skipped" "" "$(parse 1800000000 2g "$V3_5G" | rows)"
expect "a table, one row per channel (readable chanspecs)" "1800000000,'5g',36,2,0,1,0,0,-101 1800000000,'5g',40,4,0,1,266,0,-101" \
	"$(parse 1800000000 5g "$(printf 'version: 4\n%s\n36/80 3 5 2 0 1 0 90 0 0 0 0 -101 90 10 152867341\n40/80 3 3 4 0 1 0 89 0 0 266 0 -101 89 11 153774192\n' "$HDR")" | rows | tr '\n' ' ' | sed 's/ $//')"
expect "a table with hex 6 GHz chanspecs" "1800000000,'6g',1,11,0,1,0,0,-103 1800000000,'6g',5,0,0,1,0,0,-103" \
	"$(parse 1800000000 6g "$(printf 'chanspec tx inbss obss nocat nopkt doze txop goodtx badtx glitch badplcp knoise timestamp\n0x5001 0 0 11 0 1 0 100 0 0 0 0 -103 153569204\n0x5005 0 0 0 0 1 0 100 0 0 0 0 -103 152417787\n')" | rows | tr '\n' ' ' | sed 's/ $//')"
expect "one row (the radio's own channel, not a scan): nothing" "" \
	"$(parse 1800000000 5g "$(printf 'version: 4\n%s\n149/80 3 1 9 1 1 0 88 1 1 14 0 -89 90 13 152951059\n' "$HDR")")"
expect "an error from wl: nothing" "" "$(parse 1800000000 5g "wl: Unsupported")"
expect "values are clamped to 0-100%" "1800000000,'5g',36,100,0,1,0,0,-90" \
	"$(parse 1800000000 5g "$(printf 'Stats during last scan:\n chanspec: 0xd024 crsglitch cnt: 0 bad plcp: 0 noise: -90\n\t cca_obss:250 cca_nocat: 0 cca_nopkt: 1\n chanspec: 0xd028 crsglitch cnt: 0 bad plcp: 0 noise: -90\n\t cca_obss:1 cca_nocat: 0 cca_nopkt: 1\n')" | rows | head -1)"

# ---- 2: a scan on a stand-in router --------------------------------------------------------------
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
printf '%s' "$V3_2G" > "$F/chanim_eth6"; printf '%s' "$V3_5G" > "$F/chanim_eth7"
cat > "$t/bin/wl" <<EOF
#!$bb sh
F="$F"; ifc=\$2
case "\$3" in
	isup) echo 1 ;;
	chanspec) [ "\$ifc" = eth6 ] && echo "1 (0x1001)" || echo "100l (0xd866)" ;;
	channels) [ "\$ifc" = eth6 ] && echo "1 2 3 4 5 6 7 8 9 10 11 12 13" || echo "36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140" ;;
	scan) : ;;
	scanresults) printf 'SSID: "Neighbour"\nMode: Managed\tRSSI: -60 dBm\tChannel: %s\nBSSID: 02:00:00:00:00:01\tCapability: ESS\n' "\$( [ "\$ifc" = eth6 ] && echo 6 || echo 36)" ;;
	chanim_stats) [ "\$4" = all ] && [ -f "\$F/chanim_\$ifc" ] && cat "\$F/chanim_\$ifc" ;;
	*) exit 1 ;;
esac
EOF
chmod +x "$t/bin/date" "$t/bin/sleep" "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl"
awk '/^init_db\(\) \{/ { f = 1 } f && /^EOF$/ { exit } f && p { print } f && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
"$sqlite" "$D/wifiinsight.db" < "$t/schema.sql"
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@"; }
q() { "$sqlite" "$D/wifiinsight.db" "$1"; }

out=$(run scan 2>&1) || true
expect "scan: 5 GHz says how many channels were measured" "ok, 1 network in 3 s, 11 channels measured" "$(printf '%s\n' "$out" | sed -n 's/^  5g (eth7): //p')"
expect "scan: 2.4 GHz too" "ok, 1 network in 3 s, 3 channels measured" "$(printf '%s\n' "$out" | sed -n 's/^  2g (eth6): //p')"
expect "scan: measurements stored with each band's scan time" "14|14" "$(q "SELECT count(*) FROM chanim;")|$(q "SELECT count(*) FROM chanim c JOIN scans s ON s.ts=c.ts AND s.band=c.band AND s.ch=c.ch;")"
python3 - "$R/www/user/wifiinsight/scans.htm" <<'EOF' && ok "scans.htm: measured values next to the estimate" || bad "scans.htm measured values"
import json, sys
d = json.load(open(sys.argv[1]))
row = {r[1]: r for r in d['scans']['5g']}
assert row[60][6:12] == [1, 4, 8, 1, -91, 22], row[60]       # scans, others, non-Wi-Fi, unclassified, noise, glitches
assert len(row[140]) == 6, row[140]                            # channel 140 wasn't in the list: estimate only
assert len(row[36]) == 12
EOF
run export > /dev/null 2>&1 || true
python3 - "$R/www/user/wifiinsight/month.htm" <<'EOF' && ok "month.htm: measured averages and how many readings" || bad "month.htm measured values"
import json, sys
d = json.load(open(sys.argv[1]))
row = {r[1]: r for r in d['scans']['2g']}
assert row[3][7:13] == [0.0, 16.0, 16.0, -67.0, 3700.0, 1], row[3]
assert len(row[13]) == 7, row[13]                              # channel 13 wasn't measured
EOF
# a router whose driver doesn't list channels: the scan works as before
rm -f "$F/chanim_eth7"; echo 1800001800 > "$F/clock"
out=$(run scan 2>&1) || true
expect "no per-channel list: the scan reports no measurements" "ok, 1 network in 3 s" "$(printf '%s\n' "$out" | sed -n 's/^  5g (eth7): //p')"
# prune keeps the retention for measurements too
echo $(( 1800000000 + 31 * 86400 )) > "$F/clock"
run prune > /dev/null 2>&1 || true
expect "prune: measurements older than the history kept are removed" "0" "$(q "SELECT count(*) FROM chanim;")"

[ $fail -eq 0 ] && echo "Measured spectrum: all checks passed." || { echo "::error::Measured spectrum: some checks failed."; exit 1; }
