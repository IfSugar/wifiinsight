#!/bin/bash
# Regression test: the data files the page reads stay complete with a full history.
#
# Merlin's BusyBox is built without the shell's own [, printf and echo, so each runs as a
# separate program, and Linux refuses any single argument over 128 KB. A day of samples is
# ~350 KB of JSON, so it must be streamed, never held in a variable and passed on (1.0.8 did,
# and on the router its charts went empty after about 9 hours of history).
#
# This turns bash's built-in [, test, printf and echo off to behave the same way, fills a
# database with a day of samples, a week of scans and a big radar log, then checks the export.
#
# Usage: .github/tests/large-history.sh [path/to/wifiinsight.sh]   (needs sqlite3 and python3)
set -eu
export TZ=UTC   # syslog times have no zone: avoid a clock change repeating an hour of test lines
script=${1:-$(cd "$(dirname "$0")/../.." && pwd)/wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
R=$t/root; D=$t/data
mkdir -p "$R/jffs/addons/wifiinsight" "$R/www/user" "$R/tmp" "$D" "$t/bin"
printf 'SQLITE="%s"\nDATA_DIR="%s"\n' "$(command -v sqlite3)" "$D" > "$R/jffs/addons/wifiinsight/config"

# Router stand-ins: NTP synced, two radios, no driver to ask (live radio details stay empty).
cat > "$t/bin/nvram" <<'EOF'
#!/bin/sh
case "$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; wl0_ssid|wl1_ssid) echo Home ;; esac
EOF
printf '#!/bin/sh\nexit 1\n' > "$t/bin/wl"
chmod +x "$t/bin/nvram" "$t/bin/wl"

# The script's own schema, then a day of 30 s samples on two bands and a week of 30 min scans.
awk '/^init_db\(\) \{/ { f = 1 } f && /^EOF$/ { exit } f && p { print } f && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
now=$(date +%s)
sqlite3 "$D/wifiinsight.db" < "$t/schema.sql"
sqlite3 "$D/wifiinsight.db" <<EOF
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 2879)
INSERT INTO samples(ts, band, ctl, width, center, tx, inbss, obss, nocat, nopkt, doze, txop, goodtx, badtx, glitch, badplcp, knoise, idle, noise)
SELECT $now - 30 - i * 30, b, 36, 80, 42, 5, 2, 12, 3, 4, 0, 70, 5, 1, 300, 20, -92, 74, -91
FROM n, (SELECT '2g' AS b UNION ALL SELECT '5g');
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 335),
c(ch) AS (SELECT 1 UNION ALL SELECT ch + 1 FROM c WHERE ch < 16)
INSERT INTO scans SELECT $now - 60 - i * 1800, b, ch, 23.5, 4, -61, 0 FROM n, c, (SELECT '2g' AS b UNION ALL SELECT '5g');
EOF

# Over 128 KB of radar lines in the syslog.
i=0; while [ $i -lt 1800 ]; do
	echo "$(date -d "@$((now - 20 * 86400 + i * 900))" '+%b %e %H:%M:%S') router kernel: wl1: DFS: Radar detected on channel 100 (test $i)"
	i=$((i + 1))
done > "$R/tmp/syslog.log"
[ "$(wc -c < "$R/tmp/syslog.log")" -gt 131072 ] || { echo "::error::test radar log is under 128 KB"; exit 1; }

echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" PATH="$t/bin:$PATH" BASH_ENV="$t/no-builtins.sh" bash "$script" "$@"; }
run collect --once 2> "$t/err.collect" || true
run export 2> "$t/err.export"

fail=0
for f in collect export; do
	if [ -s "$t/err.$f" ]; then echo "::error::'$f' printed errors:"; cat "$t/err.$f"; fail=1; fi
done
python3 - "$R/www/user/wifiinsight" "$D/wifiinsight.db" <<'EOF' || fail=1
import json, os, sqlite3, sys
web, db = sys.argv[1:3]
def load(f):
    return json.load(open(os.path.join(web, f)))
live, scans = load('live.htm'), load('scans.htm')
load('week.htm'); load('month.htm')
con = sqlite3.connect(db)
one = lambda q: con.execute(q).fetchone()[0]
got = {
    'samples in live.htm': sum(len(v) for v in live['samples'].values()),
    'scan rows in scans.htm': sum(len(v) for v in scans['scans'].values()),
    'radar events': one("SELECT count(*) FROM events WHERE tag='radar'"),
}
# What the database holds for the windows the export used (the run itself takes a minute).
want = {
    'samples in live.htm': one(f"SELECT count(*) FROM samples WHERE ts >= {live['generated'] - 86400}"),
    'scan rows in scans.htm': one(f"SELECT count(*) FROM scans WHERE ts >= {scans['generated'] - 7 * 86400}"),
    'radar events': 1800,
}
if want['samples in live.htm'] < 5000:
    sys.exit('FAIL test setup: too few samples to cross 128 KB')
bad = [k for k in want if got[k] < want[k]]
for k in want:
    print(f"{'ok  ' if k not in bad else 'FAIL'} {k}: {got[k]} (expected {want[k]})")
sys.exit(1 if bad else 0)
EOF
[ $fail -eq 0 ] && echo "Large history: data files complete." || { echo "::error::Large history: data is lost."; exit 1; }
