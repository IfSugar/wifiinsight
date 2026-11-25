#!/bin/bash
# Regression test: rows a failing USB drive damaged can't hide a radio's data, are counted, and are removed.
#
# A flipped bit turned some of ColDen's rows (a GT-AX6000, on the forum) into radios that don't exist ("g, 0g,
# 4g, 5f), and some into a blob that still reads 2g or 5g. Blobs sort after text, so the 30-day file had two
# "2g" keys, the blob's last, and the page (like any JSON reader) kept the last: 3 stray samples instead of
# weeks, and an almost empty 30D chart, on both bands. Now every export leaves out rows whose radio isn't one
# WiFi Insight writes (2g, 5g, 6g, 5g2..., as text), status counts them (and rows over a day ahead), and the
# nightly prune removes them and logs it.
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs.
# Usage: .github/tests/damaged-rows.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, python3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::damaged-rows.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::damaged-rows.sh needs sqlite3 installed"; exit 1; }
bash_bin=$(command -v bash)
export TZ=UTC
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }

R=$t/root; D=$t/data
mkdir -p "$R/jffs/addons/wifiinsight" "$R/www/user" "$R/tmp" "$D" "$t/bin"
cp "$script" "$R/jffs/addons/wifiinsight/wifiinsight.sh"
printf 'SQLITE="%s"\nDATA_DIR="%s"\n' "$sqlite" "$D" > "$R/jffs/addons/wifiinsight/config"
"$bb" --list > "$t/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$t/bb.list"; then ln -s "$bb" "$t/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$t/bin/$a"
	fi
done
rm -f "$t/bin/logger"; printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$t" > "$t/bin/logger"
printf '#!/bin/sh\ncase "$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; esac\n' > "$t/bin/nvram"
printf '#!/bin/sh\nexit 1\n' > "$t/bin/wl"
chmod +x "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl"
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@"; }
q() { "$sqlite" "$D/wifiinsight.db" "$1"; }

# 20 days of hourly samples and 6-hourly scans on 2g and 5g, then the damaged rows: radios that don't exist,
# 2g and 5g as blobs, and a sample a week ahead; in every table.
awk '/^SCHEMA=\047/ { f = 1; sub(/^SCHEMA=\047/, "") } f { e = ($0 ~ /\047$/); if (e) sub(/\047$/, ""); print; if (e) exit }' "$script" | "$sqlite" "$D/wifiinsight.db"
now=$(date +%s)
q "WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 479)
   INSERT INTO samples(ts, band, ctl, width, center, tx, inbss, obss, nocat, nopkt, idle, noise) SELECT $now - 60 - i * 3600, b, 36, 80, 42, 5, 2, 12, 3, 4, 74, -91 FROM n, (SELECT '2g' AS b UNION ALL SELECT '5g');
   WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 79)
   INSERT INTO scans SELECT $now - 120 - i * 21600, b, 36, 20.5, 3, -60, 0 FROM n, (SELECT '2g' AS b UNION ALL SELECT '5g');"
good=$(q "SELECT (SELECT count(*) FROM samples) || ' ' || (SELECT count(*) FROM scans);")
old=$((now - 13 * 86400))
q "INSERT INTO samples(ts, band, obss, nocat, idle) VALUES ($old, '\"g', 6, 4, 86), ($old + 3600, '0g', 5, 3, 89), ($old + 7200, '4g', 5, 3, 89), ($old + 10800, '5f', 5, 3, 89),
     ($old, X'3267', 9, 1, 80), ($old + 3600, X'3267', 9, 1, 80), ($old + 7200, X'3267', 9, 1, 80), ($old, X'3567', 9, 1, 80), ($now + 7 * 86400, '2g', 50, 9, 40);
   INSERT INTO scans VALUES ($old, X'3267', 36, 20.5, 3, -60, 0), ($old, '5f', 36, 20.5, 3, -60, 0);
   INSERT INTO aps(ts, band, bssid, ssid, rssi, ctl) VALUES ($now - 120, '\"g', '02:00:00:00:00:01', 'Stray', -60, 6);
   INSERT INTO chanim(ts, band, ch, obss) VALUES ($old, '5f', 36, 5);
   INSERT INTO events(ts, band, tag) VALUES ($old, '0g', 'radar');"
damaged=14

run export 2> "$t/err" || true
[ -s "$t/err" ] && { bad "export printed errors"; sed 's/^/      | /' "$t/err"; }
python3 - "$R/www/user/wifiinsight" <<'PY' && ok "exports: only real radios, no key twice, 2g and 5g with all their data" || bad "exports carry damaged rows"
import json, os, sys
web = sys.argv[1]; problems = []
def strict(pairs):
    keys = [k for k, _ in pairs]
    dup = {k for k in keys if keys.count(k) > 1}
    if dup: problems.append('duplicate keys %s' % sorted(dup))
    return dict(pairs)
f = {n: json.load(open(os.path.join(web, n)), object_pairs_hook=strict) for n in ('live.htm', 'week.htm', 'month.htm', 'scans.htm')}
for name, d, part in (('live', f['live.htm'], 'samples'), ('week', f['week.htm'], 'agg'), ('month', f['month.htm'], 'agg'), ('month scans', f['month.htm'], 'scans'), ('scans', f['scans.htm'], 'scans'), ('last scan', f['scans.htm'], 'last_scan'), ('networks', f['scans.htm'], 'aps')):
    extra = set(d[part]) - {'2g', '5g'}
    if extra: problems.append('%s: %s' % (name, sorted(extra)))
if len(f['month.htm']['agg']['2g']) < 470 or len(f['month.htm']['agg']['5g']) < 470: problems.append('month: %d/%d hours' % (len(f['month.htm']['agg']['2g']), len(f['month.htm']['agg']['5g'])))
if any(e[1] not in ('2g', '5g', 'all') for e in f['live.htm']['events']): problems.append('events')
print('\n'.join('      ' + p for p in problems)); sys.exit(1 if problems else 0)
PY

st=$(run status 2>&1 || true)
case "$st" in *"Damaged rows: $damaged "*) ok "status: counts the $damaged damaged rows" ;; *) bad "status: no damaged-rows line"; printf '%s\n' "$st" | grep -n 'samples\|Damaged' | sed 's/^/      | /' ;; esac
expect "status: one line per real radio" "2" "$(printf '%s\n' "$st" | grep -c ' samples, last ')"

: > "$t/log"; run prune > /dev/null 2>&1 || true
expect "prune: removes the damaged rows and keeps the rest" "$good|0|0|0|0|0" "$(q "SELECT (SELECT count(*) FROM samples) || ' ' || (SELECT count(*) FROM scans);")|$(q "SELECT count(*) FROM samples WHERE typeof(band) <> 'text' OR band NOT IN ('2g', '5g') OR ts > $now")|$(q "SELECT count(*) FROM scans WHERE typeof(band) <> 'text' OR band NOT IN ('2g', '5g')")|$(q "SELECT count(*) FROM aps")|$(q "SELECT count(*) FROM chanim")|$(q "SELECT count(*) FROM events")"
grep -q "^prune: removed $damaged damaged rows (a radio or a time that can't be right). If this keeps happening, the USB drive may be failing" "$t/log" \
	&& ok "prune: says so in the syslog" || { bad "prune: syslog"; sed 's/^/      | /' "$t/log"; }
case "$(run status 2>&1 || true)" in *"Damaged rows"*) bad "status: still counts damaged rows after prune" ;; *) ok "status: nothing to count after prune" ;; esac

[ $fail -eq 0 ] && echo "Damaged rows: all checks passed." || { echo "::error::Damaged rows: some checks failed."; exit 1; }
