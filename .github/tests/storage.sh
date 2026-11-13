#!/bin/bash
# Regression test: no Entware needed. The firmware's own sqlite3 (/usr/sbin/sqlite3: 3.25.3 from Merlin
# 386.1 to 3004.388.4, 3.42.0 since) reads the history, which lives in a folder on the USB drive itself,
# <drive>/wifiinsight, as Skynet keeps its data. Installs up to 1.3.0 kept it in Entware's
# /opt/var/lib/wifiinsight: 'migrate' (which install and update run) moves it to <drive>/wifiinsight on the
# same drive, a rename that keeps the very same file, and switches to the firmware's sqlite3.
#
# FW_SQLITE_BIN: the sqlite3 to stand in for the firmware's (CI builds 3.25.3 and 3.42.0 from the Merlin
# source); the host's otherwise. Runs with Merlin's BusyBox commands only.
# Usage: FW_SQLITE_BIN=... .github/tests/storage.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::storage.sh needs busybox installed"; exit 1; }
host_sqlite=$(command -v sqlite3) || { echo "::error::storage.sh needs sqlite3 installed"; exit 1; }
fw_sqlite=${FW_SQLITE_BIN:-$host_sqlite}
bash_bin=$(command -v bash)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }
has() { if printf '%s\n' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1"; echo "      want a line with: $2"; printf '%s\n' "$3" | sed 's/^/      | /'; fi; }
echo "firmware's sqlite3 stand-in: $("$fw_sqlite" -version | cut -d' ' -f1)"

mkdir -p "$T/bin"
"$bb" --list > "$T/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$T/bb.list"; then ln -s "$bb" "$T/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$T/bin/$a"
	fi
done
rm -f "$T/bin/sleep"; printf '#!%s sh\nexit 0\n' "$bb" > "$T/bin/sleep"   # waits pass at once
printf '#!%s sh\ncase "$2" in ntp_ready) echo 1 ;; esac\n' "$bb" > "$T/bin/nvram"
chmod +x "$T/bin/sleep" "$T/bin/nvram"
echo 'enable -n test [ printf echo' > "$T/no-builtins.sh"
schema=$T/schema.sql
awk '/^init_db\(\) \{/ { f = 1 } f && /^EOF$/ { exit } f && p { print } f && /<<.EOF.$/ { p = 1 }' "$script" > "$schema"

# A router: its root, the mounts it reports, and which sqlite3 programs it has (fw, opt, both, none, badfw)
router() {   # name sqlites
	R=$T/$1; M=$R/mounts; A=$R/jffs/addons/wifiinsight
	mkdir -p "$R/tmp" "$R/usr/sbin" "$R/opt/bin" "$A"
	cp "$script" "$A/wifiinsight.sh"
	echo "rootfs / rootfs rw 0 0" > "$M"
	for s in $2; do
		case "$s" in
			fw) ln -sf "$fw_sqlite" "$R/usr/sbin/sqlite3" ;;
			opt) ln -sf "$host_sqlite" "$R/opt/bin/sqlite3" ;;
			badfw) printf '#!%s sh\necho "Error: no such function: json_array" >&2; exit 1\n' "$bb" > "$R/usr/sbin/sqlite3"; chmod +x "$R/usr/sbin/sqlite3" ;;
		esac
	done
}
drive() {   # name fstype: a USB drive Merlin has mounted at /tmp/mnt/<name>
	mkdir -p "$R/tmp/mnt/$1"; echo "/dev/sd$1 $R/tmp/mnt/$1 $2 rw,noatime 0 0" >> "$M"
}
entware_on() {   # drive: Entware installed there, /opt pointing into it
	mkdir -p "$R/tmp/mnt/$1/entware/var/lib" "$R/tmp/mnt/$1/entware/bin"
	[ -L "$R/opt/bin/sqlite3" ] && mv "$R/opt/bin/sqlite3" "$R/tmp/mnt/$1/entware/bin/sqlite3"
	rm -rf "$R/opt"; ln -s "$R/tmp/mnt/$1/entware" "$R/opt"
}
run() { WI_ROOT="$R" WI_MOUNTS="$M" TZ=UTC PATH="$T/bin" BASH_ENV="$T/no-builtins.sh" "$bash_bin" "$A/wifiinsight.sh" "$@" 2>&1; }
conf() { printf 'SQLITE="%s"\nDATA_DIR="%s"\nAMTM_UPDATE=on\n' "$1" "$2" > "$A/config"; }
fill() {   # a database with history in folder $1, written by Entware's (the host's) sqlite3
	mkdir -p "$1"; "$host_sqlite" "$1/wifiinsight.db" < "$schema"
	for i in 1 2 3 4 5; do "$host_sqlite" "$1/wifiinsight.db" "INSERT INTO samples(ts, band, obss, nocat, tx, inbss, idle, noise) VALUES($((1800000000 + i * 30)), '5g', 3, 1, 2, 1, 90, -92);"; done
	echo 19 > "$1/measured_5g"
}
inode() { ls -id "$1" | awk '{ print $1 }'; }

# 1: which sqlite3: the firmware's when it has what's needed, else Entware's, else the check says why
router fwonly fw; drive USB ext4
has "the firmware's sqlite3 is enough" "[ OK ] sqlite3 $("$fw_sqlite" -version | cut -d' ' -f1) ($R/usr/sbin/sqlite3)" "$(run check)"
router both "fw opt"; drive USB ext4
has "with Entware too, the firmware's is used" "($R/usr/sbin/sqlite3)" "$(run check | grep sqlite3)"
router badfw "badfw opt"; drive USB ext4
has "the firmware's without JSON: Entware's" "($R/opt/bin/sqlite3)" "$(run check | grep sqlite3)"
router nosqlite none; drive USB ext4
has "neither: the check says what to do" "[FAIL] No sqlite3 with JSON support" "$(run check)"

# 2: where a new install keeps the history: on the USB drive itself, Entware or not
router noentware fw; drive USB1 ext4; drive USB2 ext4
has "no Entware: the first drive" "History storage: $R/tmp/mnt/USB1/wifiinsight (ext4" "$(run check)"
router entware "fw opt"; drive USB1 ext4; drive USB2 ext4; entware_on USB2
has "Entware: the drive it's on" "History storage: $R/tmp/mnt/USB2/wifiinsight (ext4" "$(run check)"
router nodrive fw; mkdir -p "$R/tmp/mnt/USB"   # a mount point without its drive is RAM
has "no drive: the check says so" "[FAIL] No USB drive is mounted" "$(run check)"

# 3: an install from before: history in Entware's /opt/var/lib/wifiinsight, read with Entware's sqlite3
router old "fw opt"; drive USB ext4; entware_on USB
old=$R/opt/var/lib/wifiinsight; new=$R/tmp/mnt/USB/wifiinsight
fill "$old"; conf "$R/opt/bin/sqlite3" "$old"; ino=$(inode "$old/wifiinsight.db")
out=$(run migrate)
has "migrate: moved, and says so" "Moved the history to $new" "$out"
expect "migrate: the very same file, renamed (same inode)" "$ino" "$(inode "$new/wifiinsight.db" 2>/dev/null)"
expect "migrate: everything else in the folder came along" "19" "$(cat "$new/measured_5g" 2>/dev/null)"
expect "migrate: a link is left at the old path" "$new" "$(readlink "$old")"
expect "migrate: the config has the new folder and the firmware's sqlite3" "$new|$R/usr/sbin/sqlite3" \
	"$(. "$A/config"; echo "$DATA_DIR|$SQLITE")"
has "migrate: the firmware's sqlite3 reads the history" "5g: 5 samples" "$(run status)"
has "migrate: and the history is where status says" "Data:        $new/wifiinsight.db" "$(run status)"
run migrate > /dev/null
expect "migrate again: nothing changes" "$ino|$new" "$(inode "$new/wifiinsight.db")|$(readlink "$old")"
"$host_sqlite" "$new/wifiinsight.db" "PRAGMA integrity_check;" | grep -qx ok && ok "migrate: Entware's sqlite3 still reads it after the firmware's wrote" || bad "integrity after migrate"

# 4: never moved while sampling or a scan holds the database, nor onto a folder that isn't empty, nor off a drive
router busy "fw opt"; drive USB ext4; entware_on USB
old=$R/opt/var/lib/wifiinsight; fill "$old"; conf "$R/opt/bin/sqlite3" "$old"
mkdir -p "$R/tmp/wifiinsight"; ( exec 6>"$R/tmp/wifiinsight/collect.lock"; flock 6; sleep 30 ) & held=$!; command sleep 0.5
has "busy: not moved while sampling" "Sampling is still running: the history stays in $old" "$(run migrate)"
kill $held 2>/dev/null; wait $held 2>/dev/null || true
[ -d "$old" ] && [ ! -L "$old" ] && ok "busy: still in place" || bad "busy: moved anyway"
mkdir -p "$R/tmp/mnt/USB/wifiinsight"; echo keep > "$R/tmp/mnt/USB/wifiinsight/other"
has "taken: not moved onto a folder that isn't empty" "already exists and isn't empty" "$(run migrate)"
router ram "fw opt"; mkdir -p "$R/tmp/opt"; rm -rf "$R/opt"; ln -s "$R/tmp/opt" "$R/opt"; echo "tmpfs $R/tmp tmpfs rw 0 0" >> "$M"
old=$R/opt/var/lib/wifiinsight; fill "$old"; conf "$R/usr/sbin/sqlite3" "$old"
run migrate > /dev/null
[ -d "$old" ] && [ ! -L "$old" ] && ok "RAM: a folder that isn't on a drive isn't moved" || bad "RAM: moved"

# 5: the history is never kept in RAM: a drive's mount point without the drive doesn't count
router unplugged fw; mkdir -p "$R/tmp/mnt/USB"; echo "tmpfs $R/tmp tmpfs rw 0 0" >> "$M"
fill "$R/tmp/mnt/USB/wifiinsight"; conf "$R/usr/sbin/sqlite3" "$R/tmp/mnt/USB/wifiinsight"
has "unplugged: not ready, so nothing is written to RAM" "Ready:       no" "$(run status)"

[ $fail -eq 0 ] && echo "Storage: all checks passed." || { echo "::error::Storage: some checks failed."; exit 1; }
