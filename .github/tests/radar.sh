#!/bin/bash
# Regression test: radar lines in the syslog become radar events, each with the right time and radio.
#
# Up to 1.3.0 each line went through a dozen small programs (cut, awk, date -d, nvram, wl...): about a
# minute for a log with 1800 radar lines, run again whenever a new one appeared. Now it's one awk pass,
# and sqlite turns the log's local time into epoch seconds ('utc' reads it as local time, as date -d did).
# The expected times here come from date -d, line by line, as the old code did, in a time zone with
# summer time (Sofia, whose change falls inside the log), plus a date over a day ahead (last year's).
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs.
# Usage: .github/tests/radar.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::radar.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::radar.sh needs sqlite3 installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }
export TZ="EET-2EEST,M3.5.0/3,M10.5.0/4"

mkdir -p "$t/bin"
"$bb" --list > "$t/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$t/bb.list"; then ln -s "$bb" "$t/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$t/bin/$a"
	fi
done
# GT-AX11000 layout: 2.4 GHz, 5 GHz-1 and 5 GHz-2
cat > "$t/bin/nvram" <<'EOF'
#!/bin/sh
case "$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; wl2_ifname) echo eth8 ;; wl0_nband) echo 2 ;; wl1_nband|wl2_nband) echo 1 ;; esac
EOF
cat > "$t/bin/wl" <<'EOF'
#!/bin/sh
case "$2:$3" in eth6:chanspec) echo "6 (0x1006)" ;; eth7:chanspec) echo "36/80 (0xe02a)" ;; eth8:chanspec) echo "100/80 (0xe06a)" ;; *:isup) echo 1 ;; *) exit 1 ;; esac
EOF
# date counts its calls: the old code ran date -d for every line
rm -f "$t/bin/date"; printf '#!%s sh\necho x >> "%s/date.calls"\nexec "%s" date "$@"\n' "$bb" "$t" "$bb" > "$t/bin/date"
chmod +x "$t/bin/nvram" "$t/bin/wl" "$t/bin/date"
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
R=$t/root; D=$t/data; mkdir -p "$R/jffs/addons/wifiinsight" "$R/tmp" "$D"
printf 'SQLITE="%s"\nDATA_DIR="%s"\n' "$sqlite" "$D" > "$R/jffs/addons/wifiinsight/config"
awk '/^SCHEMA=\047/ { f = 1; sub(/^SCHEMA=\047/, "") } f { e = ($0 ~ /\047$/); if (e) sub(/\047$/, ""); print; if (e) exit; next } /^init_db\(\) \{/ { h = 1 } h && /^EOF$/ { exit } h && p { print } h && /<<.EOF.$/ { p = 1 }' "$script" | "$sqlite" "$D/wifiinsight.db"
run() { WI_ROOT="$R" PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$script" "$@"; }
events() { "$sqlite" "$D/wifiinsight.db" "SELECT ts || ' ' || band || ' ' || detail FROM events WHERE tag='radar' ORDER BY ts, band, detail"; }

# A log over the last 30 days (summer time ends inside it), naming the radio as ethN, wlN or not at all,
# one line dated ahead (so last year's), and lines that aren't dated as syslog lines are (skipped).
now=$(date +%s); y=$(date +%Y)
: > "$t/want"
i=0; while [ $i -lt 120 ]; do
	at=$((now - 30 * 86400 + i * 21600 + 7))
	case $((i % 4)) in
		0) w="wl1: DFS:"; b="5g Radar detected on eth7" ;;
		1) w="eth8: wl2:"; b="5g2 Radar detected on eth8" ;;
		2) w="eth7 DFS"; b="5g Radar detected on eth7" ;;
		3) w="dfs:"; b="5g Radar detected" ;;
	esac
	stamp=$(date -d "@$at" '+%b %e %H:%M:%S')
	echo "$stamp router kernel: $w Radar detected on channel 100 (test $i)" >> "$R/tmp/syslog.log"
	echo "$(date -d "$y-$(date -d "@$at" +%m-%d) $(date -d "@$at" +%H:%M:%S)" +%s) $b" >> "$t/want"
	i=$((i + 1))
done
ahead=$((now + 40 * 86400)); md=$(date -d "@$ahead" +%m-%d); hms=$(date -d "@$ahead" +%H:%M:%S)
echo "$(date -d "@$ahead" '+%b %e %H:%M:%S') router kernel: eth7: Radar detected" >> "$R/tmp/syslog.log"
echo "$(date -d "$((y - 1))-$md $hms" +%s) 5g Radar detected on eth7" >> "$t/want"
printf 'Foo 13 12:00:00 router kernel: Radar detected\nNov 13 1:00:00 router kernel: Radar detected\n2026-11-13T12:00:00+02:00 router kernel: Radar detected\n' >> "$R/tmp/syslog.log"
sort -n -k1,1 -k2,2 -k3 "$t/want" | sort -u > "$t/want.sorted"

: > "$t/date.calls"; run collect --once 2> "$t/err" || true; dates=$(wc -l < "$t/date.calls" | tr -d ' ')
[ -s "$t/err" ] && { bad "collect printed errors"; sed 's/^/      | /' "$t/err"; }
events | sort -u > "$t/got"
if cmp -s "$t/want.sorted" "$t/got"; then ok "every line: the same time as date -d gives, and its radio ($(wc -l < "$t/got") events)"
else bad "events differ from date -d's"; diff "$t/want.sorted" "$t/got" | head -8 | sed 's/^/      | /'; fi
expect "a date ahead is last year's" "1" "$(grep -c "^$(date -d "$((y - 1))-$md $hms" +%s) " "$t/got")"
expect "lines not dated as syslog lines are skipped" "0" "$(grep -c 'Foo\|T12:00' "$t/got" || true)"
[ "$dates" -lt 40 ] && ok "one pass: $dates calls to date for $(wc -l < "$t/got") lines" || bad "a call to date per line: $dates calls"

# Read again (a new line arrives): nothing doubles, and the new one is added
echo "$(date -d "@$((now - 60))" '+%b %e %H:%M:%S') router kernel: wl1: Radar detected on channel 52" >> "$R/tmp/syslog.log"
run collect --once 2> /dev/null || true
expect "read again: only the new line is added" "$(( $(wc -l < "$t/got") + 1 ))" "$(events | wc -l | tr -d ' ')"

[ $fail -eq 0 ] && echo "Radar: all checks passed." || { echo "::error::Radar: some checks failed."; exit 1; }
