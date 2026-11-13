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
rm -f "$t/bin/logger" "$t/bin/date"
printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$F" > "$t/bin/logger"
# date +%w (the weekday prune compacts on) can be set in $F/wday
printf '#!%s sh\nif [ "$*" = "+%%w" ] && [ -f "%s/wday" ]; then cat "%s/wday"; else exec "%s" date "$@"; fi\n' "$bb" "$F" "$F" "$bb" > "$t/bin/date"
chmod +x "$t/bin/date"
printf '#!/bin/sh\ncase "$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; esac\n' > "$t/bin/nvram"
printf '#!/bin/sh\nexit 1\n' > "$t/bin/wl"
chmod +x "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl"
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" WI_MOUNTS="${MOUNTS:-}" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@"; }
q() { "$sqlite" "$D/wifiinsight.db" "$1"; }
live() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("damaged", "missing"))' "$R/www/user/wifiinsight/live.htm"; }

# A database with a day of samples and a week of scans, the way WiFi Insight writes it
awk '/^SCHEMA=\047/ { f = 1; sub(/^SCHEMA=\047/, "") } f { e = ($0 ~ /\047$/); if (e) sub(/\047$/, ""); print; if (e) exit; next } /^init_db\(\) \{/ { h = 1 } h && /^EOF$/ { exit } h && p { print } h && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
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

# 5: damage only the full check finds (an index whose entries no longer match its table): quick_check says
# ok, so repair has to run integrity_check. The index's definition stays WiFi Insight's own (one that isn't
# is refused, see storage.sh): it's rebuilt on another column, then its definition put back.
python3 - "$D/wifiinsight.db" <<'PY'
import sqlite3, sys
db = sys.argv[1]
def schema(sql):
    c = sqlite3.connect(db); c.execute('PRAGMA writable_schema=ON')
    c.execute("UPDATE sqlite_master SET sql=? WHERE name='sa_ts'", (sql,)); c.commit(); c.close()
schema('CREATE INDEX sa_ts ON samples(obss)')
c = sqlite3.connect(db); c.execute('REINDEX sa_ts'); c.commit(); c.close()
schema('CREATE INDEX sa_ts ON samples(ts)')
PY
expect "index damage: quick_check misses it" "ok" "$(q "PRAGMA quick_check")"
out=$(run repair 2>&1) || true
has "index damage: found" "It's damaged:" "$out"
has "index damage: repaired" "Repaired: kept " "$out"
expect "index damage: sound afterwards" "ok" "$(q "PRAGMA integrity_check")"

# 6: the weekly compaction: only on Sunday, only when a quarter or more of the file is free pages
python3 - "$D/wifiinsight.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executemany('insert into samples(ts,band,obss) values(?,?,?)', [(i, '9g', 1) for i in range(40000)])
c.commit(); c.execute("delete from samples where band='9g'"); c.commit(); c.close()
PY
free() { q "PRAGMA freelist_count"; }
echo 3 > "$F/wday"; run prune > /dev/null 2>&1 || true
[ "$(free)" -gt 0 ] && ok "compaction: not on a Wednesday" || bad "compaction ran on a Wednesday"
echo 0 > "$F/wday"; run prune > /dev/null 2>&1 || true
expect "compaction: on Sunday with many free pages" "0" "$(free)"
grep -q '^database compacted (.* of .* pages were free)$' "$F/log" && ok "compaction: logged" || bad "compaction: syslog"
n=$(grep -c 'database compacted' "$F/log"); run prune > /dev/null 2>&1 || true
expect "compaction: not again when there's little to gain" "$n" "$(grep -c 'database compacted' "$F/log")"
expect "compaction: still sound" "ok" "$(q "PRAGMA integrity_check")"

# 7: a drive without a journal (ext2, FAT, NTFS, or ext4 made without one) is flagged in check, status,
# debug and live.htm; ext4 with a journal (it has /proc/fs/jbd2/<device>-8) isn't
fsjson() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d.get("fs"), "|", d.get("fs_note"))' "$R/www/user/wifiinsight/live.htm"; }
MOUNTS=$t/mounts; P=$(cd "$t" && pwd -P); mkdir -p "$t/proc/fs/jbd2"
mounts() { printf 'rootfs / rootfs rw 0 0\n/dev/sda1 %s %s rw,noatime 0 0\n' "$P" "$1" > "$MOUNTS"; }
runp() { WI_PROC="$t/proc" run "$@" 2>&1 || true; }
NOTE2="The drive is ext2, which has no journal, so a power cut while it's writing can damage the history database. ext4 with a journal is safer"
mounts ext2
has "ext2: status warns" "Storage:     ext2. $NOTE2" "$(runp status)"
has "ext2: check warns" "[WARN] History storage: $NOTE2" "$(runp check)"
has "ext2: debug names it" "Storage: $D on ext2" "$(runp debug)"
runp export > /dev/null
has "ext2: the page is told" "ext2 | $NOTE2" "$(fsjson)"
mounts ext4
has "ext4 without a journal: status warns" "Storage:     ext4. The drive is ext4 without a journal, so a power cut" "$(runp status)"
mkdir -p "$t/proc/fs/jbd2/sda1-8"
out=$(runp status)
has "ext4 with a journal: status names it" "Storage:     ext4" "$out"
hasnt "ext4 with a journal: no warning" "journal" "$out$(runp check)"
runp export > /dev/null
expect "ext4 with a journal: nothing for the page" "ext4 | " "$(fsjson)"
mounts ext3; rm -rf "$t/proc/fs/jbd2/sda1-8"
hasnt "ext3: always has a journal, no jbd2 entry needed" "journal" "$(runp status)$(runp check)"
mounts ext4
rm -rf "$t/proc/fs/jbd2"
hasnt "no jbd2 in /proc: no guessing" "journal" "$(runp status)"
MOUNTS=""

[ $fail -eq 0 ] && echo "Repair: all checks passed." || { echo "::error::Repair: some checks failed."; exit 1; }
