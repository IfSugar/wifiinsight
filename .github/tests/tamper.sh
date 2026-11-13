#!/bin/bash
# Regression test: a history folder others can write to can't be turned against the router.
#
# The history lives on the USB drive, which a guest Samba or anonymous FTP share, or anyone with the drive
# in hand, can write to. A database with a table, trigger or view WiFi Insight didn't create could make
# sqlite3 write files as root: a CHECK constraint calling writefile() does, even on 3.42.0. So every
# sqlite3 run checks the schema first and stops if it holds anything else; repair won't touch such a
# database either. A measured_* file name can't inject into the page's JSON, and the small files written
# there, and the database itself, are never written through a link someone left.
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs.
# Usage: .github/tests/tamper.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, python3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::tamper.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::tamper.sh needs sqlite3 installed"; exit 1; }
bash_bin=$(command -v bash)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }
has() { if printf '%s\n' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1"; echo "      want a line with: $2"; printf '%s\n' "$3" | sed 's/^/      | /'; fi; }

mkdir -p "$T/bin"
"$bb" --list > "$T/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$T/bb.list"; then ln -s "$bb" "$T/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$T/bin/$a"
	fi
done
rm -f "$T/bin/logger"; printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$T" > "$T/bin/logger"
cat > "$T/bin/nvram" <<'EOF'
#!/bin/sh
case "$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; wl0_nband) echo 2 ;; wl1_nband) echo 1 ;; esac
EOF
cat > "$T/bin/wl" <<'EOF'
#!/bin/sh
case "$2:$3" in
	eth6:chanspec) echo "6 (0x1006)" ;; eth7:chanspec) echo "36/80 (0xe02a)" ;; *:isup) echo 1 ;;
	*:chanim_stats) printf 'version: 4\nchspec tx inbss obss nocat nopkt doze txop goodtx badtx glitch badplcp knoise idle busy timestamps\n%s 1 0 4 1 1 0 96 0 0 1 0 -92 90 4 %s\n' "$( [ "$2" = eth6 ] && echo 6 || echo 36/80)" "$(date +%s%N)" ;;
	*) exit 1 ;;
esac
EOF
chmod +x "$T/bin/logger" "$T/bin/nvram" "$T/bin/wl"
echo 'enable -n test [ printf echo' > "$T/no-builtins.sh"
schema=$T/schema.sql
awk '/^SCHEMA=\047/ { f = 1; sub(/^SCHEMA=\047/, "") } f { e = ($0 ~ /\047$/); if (e) sub(/\047$/, ""); print; if (e) exit; next } /^init_db\(\) \{/ { h = 1 } h && /^EOF$/ { exit } h && p { print } h && /<<.EOF.$/ { p = 1 }' "$script" > "$schema"

fresh() {   # a router with an installed WiFi Insight and its history folder
	R=$T/$1; D=$R/data; mkdir -p "$R/jffs/addons/wifiinsight" "$R/tmp" "$D"
	cp "$script" "$R/jffs/addons/wifiinsight/wifiinsight.sh"
	printf 'SQLITE="%s"\nDATA_DIR="%s"\nAMTM_UPDATE=on\n' "$sqlite" "$D" > "$R/jffs/addons/wifiinsight/config"
	: > "$T/log"
}
run() { WI_ROOT="$R" TZ=UTC PATH="$T/bin" BASH_ENV="$T/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@" 2>&1; }
planted() {   # the database someone put in the folder: WiFi Insight's tables, plus $1
	"$sqlite" "$D/wifiinsight.db" < "$schema"
	"$sqlite" "$D/wifiinsight.db" "$1"
}

# 1: a CHECK constraint calling writefile(): sqlite3 would write the file as root on every insert
fresh check
planted "DROP TABLE state; CREATE TABLE state(k TEXT PRIMARY KEY, v TEXT CHECK(writefile('$T/pwned-check', 'x') >= 0));"
out=$(run collect --once) || true
[ ! -e "$T/pwned-check" ] && ok "CHECK writefile(): never runs" || bad "CHECK writefile() wrote $T/pwned-check"
has "CHECK: the syslog says why the database isn't used" "holds something WiFi Insight didn't create (state), so it isn't used" "$(cat "$T/log")"
has "CHECK: status says so" "Database:    NOT USED" "$(run status)"
out=$(run repair) || true
has "CHECK: repair refuses it" "so it won't be repaired or used" "$out"
[ ! -e "$T/pwned-check" ] && [ -f "$D/wifiinsight.db" ] && [ ! -f "$D/wifiinsight.db.bad" ] && ok "CHECK: repair left it alone and ran nothing" || bad "CHECK: repair touched it"

# 2: a trigger, a view in place of a table, an extra table
for kind in trigger view; do
	fresh "$kind"
	case $kind in
		trigger) planted "CREATE TABLE t2(a); CREATE TRIGGER x AFTER INSERT ON state BEGIN INSERT INTO t2 SELECT writefile('$T/pwned-$kind', 'x'); END;" ;;
		view) planted "DROP TABLE events; CREATE VIEW events AS SELECT writefile('$T/pwned-$kind', 'x') AS ts, 1 AS band, 1 AS tag, 1 AS old, 1 AS new, 1 AS detail;" ;;
	esac
	run collect --once > /dev/null || true; run status > /dev/null || true; run export > /dev/null || true
	[ ! -e "$T/pwned-$kind" ] && ok "$kind with writefile(): never runs" || bad "$kind with writefile() wrote a file"
	has "$kind: refused" "didn't create" "$(cat "$T/log")"
done

# 3: WiFi Insight's own database (with sqlite's own statistics table, which prune's PRAGMA optimize makes) works
fresh own
"$sqlite" "$D/wifiinsight.db" < "$schema"; "$sqlite" "$D/wifiinsight.db" "INSERT INTO samples(ts, band) VALUES(1, '5g'); ANALYZE;"
run collect --once > /dev/null || true
expect "own database (with sqlite_stat1): used" "1" "$("$sqlite" "$D/wifiinsight.db" "SELECT count(*) > 1 FROM samples")"
[ -s "$T/log" ] && { bad "own database: unexpected syslog lines"; sed 's/^/      | /' "$T/log"; } || ok "own database: nothing logged"

# 4: a measured_* file name can't inject into live.htm; only radio keys are exported
fresh names
"$sqlite" "$D/wifiinsight.db" < "$schema"
echo 19 > "$D/measured_5g"
echo 1 > "$D/measured_x\":0},\"version\":\"<img src=x onerror=alert(1)>\",\"zz\":{\"y"
echo 2 > "$D/measured_a\\b"
run collect --once > /dev/null || true
python3 - "$R/www/user/wifiinsight/live.htm" <<'PY' && ok "measured_* names: live.htm is valid JSON with only radio keys, and its version intact" || bad "measured_* names leak into live.htm"
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d['measured'] == {'5g': 19} and not d['version'].startswith('<') else 1)
PY

# 5: links left in the folder are never written through: the small files, and the database itself
fresh links
echo "not a database" > "$D/wifiinsight.db"   # damaged: WiFi Insight writes the 'damaged' file
echo keep > "$T/target-damaged"; ln -s "$T/target-damaged" "$D/damaged"
run collect --once > /dev/null || true
expect "link as 'damaged': its target untouched" "keep" "$(cat "$T/target-damaged")"
[ -f "$D/damaged" ] && [ ! -L "$D/damaged" ] && ok "link as 'damaged': replaced by WiFi Insight's own file" || bad "link as 'damaged' still there"
fresh dblink
"$sqlite" "$T/other.db" < "$schema"; ln -s "$T/other.db" "$D/wifiinsight.db"
run collect --once > /dev/null || true
expect "database replaced by a link: not used (the link's target unchanged)" "0" "$("$sqlite" "$T/other.db" "SELECT count(*) FROM samples")"
has "database replaced by a link: not ready" "Ready:       no" "$(run status)"

[ $fail -eq 0 ] && echo "Tamper: all checks passed." || { echo "::error::Tamper: some checks failed."; exit 1; }
