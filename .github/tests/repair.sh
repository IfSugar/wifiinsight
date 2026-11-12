#!/bin/bash
# Regression test: a damaged database is noticed, reported, and repaired.
#
# After a power cut, a GT-AX6000's database on its USB drive said "database disk image is malformed":
# status printed the error, and the page showed nothing about it. Now:
#  - any sqlite "malformed" / "not a database" error marks the database as damaged (once, logged),
#  - status ends with a DAMAGED line and live.htm carries "damaged" for the page,
#  - 'repair' rebuilds it from everything readable (sqlite3 .dump; .recover isn't in every build),
#    keeps the damaged copy as .bad, and clears the mark; on a sound database it changes nothing.
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs.
# Usage: .github/tests/repair.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, python3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::repair.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::repair.sh needs sqlite3 installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1"; echo "      want it to contain: $2"; printf '%s\n' "$3" | sed 's/^/      | /' ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1"; printf '%s\n' "$3" | sed 's/^/      | /' ;; *) ok "$1" ;; esac; }

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
rm -f "$t/bin/logger"
printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$F" > "$t/bin/logger"
printf '#!/bin/sh\ncase "$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; esac\n' > "$t/bin/nvram"
printf '#!/bin/sh\nexit 1\n' > "$t/bin/wl"
chmod +x "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl"
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@"; }
q() { "$sqlite" "$D/wifiinsight.db" "$1"; }
live() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("damaged", "missing"))' "$R/www/user/wifiinsight/live.htm"; }

# A database with a day of samples and a week of scans, the way WiFi Insight writes it
awk '/^init_db\(\) \{/ { f = 1 } f && /^EOF$/ { exit } f && p { print } f && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
"$sqlite" "$D/wifiinsight.db" < "$t/schema.sql"
now=$(date +%s)
python3 - "$D/wifiinsight.db" "$now" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); t0 = int(sys.argv[2])
c.executemany('insert into samples(ts,band,obss,nocat,tx,inbss,idle,noise) values(?,?,?,?,?,?,?,?)',
              [(t0 - i * 30, b, i % 7, 1, 2, 3, 90, -90) for i in range(2880) for b in ('2g', '5g')])
c.executemany('insert into scans(ts,band,ch,score,aps) values(?,?,?,?,?)',
              [(t0 - i * 1800, '5g', ch, 1.0, 2) for i in range(336) for ch in (36, 40, 44, 48)])
c.execute("insert into events values(?, '5g', 'auto', '100/80', '36/160', '')", (t0,))
c.commit(); c.close()
PY

# 1: a sound database: repair changes nothing
out=$(run repair 2>&1) || true
has "sound: nothing to repair" "The database is fine: nothing to repair." "$out"
[ ! -f "$D/wifiinsight.db.bad" ] && ok "sound: no copy made" || bad "sound: a .bad copy appeared"

# 2: damage some table pages (as a power cut mid-write can)
python3 - "$D/wifiinsight.db" <<'PY'
import sys
p = sys.argv[1]; d = bytearray(open(p, 'rb').read()); pg = 4096
for n in (20, 21, 22, 60):
    d[n * pg + 100:n * pg + 900] = b'\xff' * 800
open(p, 'wb').write(d)
PY
before=$(q "SELECT count(*) FROM samples")
run export > /dev/null 2>&1 || true   # what collect does every minute: reads the last day's samples
[ -f "$D/damaged" ] && ok "damaged: noticed while exporting" || bad "damaged: not noticed"
grep -q "the database is damaged (.*malformed.*): run '.*wifiinsight.sh repair'" "$F/log" && ok "damaged: logged" || { bad "damaged: syslog"; cat "$F/log"; }
run export > /dev/null 2>&1 || true
expect "damaged: logged once" "1" "$(grep -c 'the database is damaged' "$F/log")"
expect "damaged: the page is told when" "$(cat "$D/damaged")" "$(live)"
out=$(run status 2>&1) || true
has "damaged: status says so" "Database:    DAMAGED (noticed " "$out"
has "damaged: status says what to run" "wifiinsight.sh repair'." "$out"

# 3: repair
out=$(run repair 2>&1) || true
has "repair: says what's wrong" "It's damaged:" "$out"
has "repair: done" "Repaired: kept " "$out"
has "repair: points at the damaged copy" "The damaged copy is $D/wifiinsight.db.bad" "$out"
expect "repair: the new database is sound" "ok" "$(q "PRAGMA integrity_check")"
after=$(q "SELECT count(*) FROM samples")
[ "$after" -gt $((before * 8 / 10)) ] && ok "repair: kept most samples ($after of $before)" || bad "repair: kept $after of $before samples"
expect "repair: scans and events kept" "336|1" "$(q "SELECT count(DISTINCT ts) FROM scans")|$(q "SELECT count(*) FROM events")"
expect "repair: tables and indexes all there" "6|1" "$(q "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('samples','events','scans','aps','chanim','state')")|$(q "SELECT count(*) FROM sqlite_master WHERE name='sa_ts'")"
[ -f "$D/wifiinsight.db.bad" ] && ok "repair: damaged copy kept" || bad "repair: no .bad copy"
[ ! -f "$D/damaged" ] && ok "repair: mark cleared" || bad "repair: still marked damaged"
grep -q '^database repaired, kept .* samples and .* scans; the damaged copy is ' "$F/log" && ok "repair: logged" || bad "repair: syslog"
run export > /dev/null 2>&1 || true
expect "repair: the page is told it's fine" "None" "$(live)"
out=$(run status 2>&1) || true
hasnt "repair: status is clean" "DAMAGED" "$out"
hasnt "repair: no sqlite errors in status" "malformed" "$out"

# 4: repair again: nothing to do, and the .bad copy stays as it was
m=$(ls -l "$D/wifiinsight.db.bad" | awk '{ print $5 }')
out=$(run repair 2>&1) || true
has "again: nothing to repair" "The database is fine: nothing to repair." "$out"
expect "again: .bad untouched" "$m" "$(ls -l "$D/wifiinsight.db.bad" | awk '{ print $5 }')"

[ $fail -eq 0 ] && echo "Repair: all checks passed." || { echo "::error::Repair: some checks failed."; exit 1; }
