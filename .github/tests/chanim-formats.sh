#!/bin/bash
# Regression test: both layouts of the driver's airtime statistics (wl chanim_stats) parse,
# using real output from routers, with BusyBox awk like on the router.
#
# Wi-Fi 6 drivers (RT-AX86U, 3004.388): "version: 3", a "chanspec" header, hex chanspecs.
# Wi-Fi 7 drivers (RT-BE88U, 3006.102): "version: 4", a "chspec" header, readable chanspecs
# (6, 36/160), "timestamps", and an extra "busy" column.
#
# Usage: .github/tests/chanim-formats.sh [path/to/wifiinsight.sh]   (needs busybox)
set -eu
script=${1:-$(cd "$(dirname "$0")/../.." && pwd)/wifiinsight.sh}
bb=$(command -v busybox) || { echo "::error::chanim-formats.sh needs busybox installed"; exit 1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"; ln -s "$bb" "$t/bin/awk"
sed -n '/^parse_chanim() {/,/^}/p' "$script" > "$t/parse.sh"
# The support check's header test, taken from the script itself.
pat=$(sed -n "s/.*chanim_stats 2>\/dev\/null | grep -E '\([^']*\)'.*/\1/p" "$script" | head -1)
[ -n "$pat" ] || { echo "::error::couldn't find the support check's chanim_stats header test"; exit 1; }

fail=0
expect() {   # name cs hex want input
	got=$(printf '%b' "$5" | PATH="$t/bin:$PATH" sh -c ". '$t/parse.sh'; parse_chanim '$2' '$3'") || got="(no result)"
	if [ "$got" = "$4" ]; then echo "ok    parse: $1"
	else echo "FAIL  parse: $1"; echo "      want: $4"; echo "      got:  $got"; fail=1; fi
	if printf '%b' "$5" | grep -qE "$pat"; then echo "ok    check: $1"
	elif [ "$4" = "(no result)" ]; then echo "ok    check: $1 (refused, as it should be)"
	else echo "FAIL  check: $1 header not recognised"; fail=1; fi
}

V3_HDR='chanspec tx   inbss   obss   nocat   nopkt   doze     txop     goodtx  badtx   glitch   badplcp  knoise  idle  timestamp'
V4_HDR='chspec tx inbss obss nocat nopkt doze txop goodtx badtx glitch badplcp knoise idle busy timestamps'

expect "RT-AX86U 2.4 GHz (version 3)" 1 0x1001 \
	"0x1001 5 2 12 3 4 0 74 1 1 1240 41 -82 78 22679864" \
	"version: 3\n$V3_HDR\n0x1001\t5\t2\t12\t3\t4\t0\t74\t1\t1\t1240\t41\t-82\t78\t22679864\n"
expect "RT-AX86U 5 GHz (version 3)" 100l 0xd866 \
	"0xd866 7 2 3 3 1 0 86 5 1 8 1 -90 93 99319339" \
	"version: 3\n$V3_HDR\n0xd866\t7\t2\t3\t3\t1\t0\t86\t5\t1\t8\t1\t-90\t93\t99319339\n"
expect "RT-BE88U 2.4 GHz (version 4)" 6 0x1006 \
	"6 7 1 11 1 6 0 77 1 0 379 15 -83 84 363643185" \
	"version: 4\n$V4_HDR\n6 7 1 11 1 6 0 77 1 0 379 15 -83 84 24 363643185\n"
expect "RT-BE88U 5 GHz 160 MHz (version 4)" 36/160 0xe832 \
	"36/160 9 3 7 2 1 0 82 2 1 2 0 -89 90 363636092" \
	"version: 4\n$V4_HDR\n36/160 9 3 7 2 1 0 82 2 1 2 0 -89 90 19 363636092\n"
expect "several rows: the radio's current channel wins" 36/160 0xe832 \
	"36/160 9 3 7 2 1 0 82 2 1 2 0 -89 90 1" \
	"version: 4\n$V4_HDR\n36/160 9 3 7 2 1 0 82 2 1 2 0 -89 90 19 1\n100/80 1 1 1 1 1 0 1 1 1 1 1 -90 99 1 2\n"
expect "driver refuses the request" 6 0x1006 "(no result)" "failed to get chanim results"

[ $fail -eq 0 ] && echo "chanim_stats: both layouts parse." || { echo "::error::chanim_stats parsing is broken."; exit 1; }
