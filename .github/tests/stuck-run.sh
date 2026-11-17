#!/bin/bash
# Regression test: a run stuck in a command that never returns doesn't stop sampling for good (issue #28).
#
# On some firmware, nvram get can wait for good for an answer from the kernel. Up to 2.1.0, a collect
# run stuck in it kept the sampling lock, and every later run skipped without a word: no samples for
# hours, until a reboot. Here an nvram stand-in really blocks (it opens a FIFO nobody writes to), and:
#  1. a stuck run younger than a run ever takes is left alone;
#  2. once it's older (its note moved back 6 minutes), the next run stops it and all it started, logs
#     what it was stuck in, takes the lock and samples;
#  3. a command left holding the lock after its run is gone is stopped too;
#  4. a prune (which can take long) is never stopped; the skipped run says so in the log, once in 30 min;
#  5. a stuck scan is stopped the same way, by the next scan;
#  6. status says sampling looks stuck when the last sample is over 10 minutes old.
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs.
# Usage: .github/tests/stuck-run.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3, flock)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::stuck-run.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::stuck-run.sh needs sqlite3 installed"; exit 1; }
hflock=$(command -v flock) || { echo "::error::stuck-run.sh needs flock installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d)
# On the way out, whatever this suite left running: only processes that are still its own (a stand-in from
# $t, or a run with this suite's WI_ROOT), never a PID noted earlier: by now it may be another suite's.
cleanup() {
	for d in /proc/[0-9]*; do
		if grep -qsF "$t/" "$d/cmdline" || grep -qsF "WI_ROOT=$t/" "$d/environ"; then kill -9 "${d#/proc/}" 2> /dev/null || true; fi
	done
	rm -rf "$t"
}
trap cleanup EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }

mkdir -p "$t/bin"
"$bb" --list > "$t/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$t/bb.list"; then ln -s "$bb" "$t/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$t/bin/$a"
	fi
done
mkfifo "$t/fifo"
# nvram: blocks for good on wl1_ifname while $t/hang exists (it notes its PID in $t/hung first)
cat > "$t/bin/nvram" <<EOF
#!/bin/sh
if [ "\$2" = wl1_ifname ] && [ -f "$t/hang" ]; then echo \$\$ > "$t/hung"; read x < "$t/fifo"; fi
case "\$2" in ntp_ready) echo 1 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; wl0_nband) echo 2 ;; wl1_nband) echo 1 ;; esac
EOF
cat > "$t/bin/wl" <<'EOF'
#!/bin/sh
case "$2:$3" in eth6:chanspec) echo "6 (0x1006)" ;; eth7:chanspec) echo "36/80 (0xe02a)" ;; *:isup) echo 1 ;; *) exit 1 ;; esac
EOF
rm -f "$t/bin/logger"; printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$t" > "$t/bin/logger"
chmod +x "$t/bin/nvram" "$t/bin/wl" "$t/bin/logger"
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
R=$t/root; D=$t/data; TM=$R/tmp/wifiinsight; mkdir -p "$R/jffs/addons/wifiinsight" "$R/www/user" "$TM" "$D"
printf 'SQLITE="%s"\nDATA_DIR="%s"\n' "$sqlite" "$D" > "$R/jffs/addons/wifiinsight/config"
awk '/^SCHEMA=\047/ { f = 1; sub(/^SCHEMA=\047/, "") } f { e = ($0 ~ /\047$/); if (e) sub(/\047$/, ""); print; if (e) exit; next } /^init_db\(\) \{/ { h = 1 } h && /^EOF$/ { exit } h && p { print } h && /<<.EOF.$/ { p = 1 }' "$script" | "$sqlite" "$D/wifiinsight.db"
run() { WI_ROOT="$R" PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$script" "$@"; }

held() { ! "$hflock" -n "$TM/$1.lock" true; }   # is the lock taken?
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null && [ "$(awk '{ print $3 }' "/proc/$1/stat" 2>/dev/null)" != Z ]; }
start_stuck() {   # action: a run of it, stuck in nvram get wl1_ifname with its lock taken
	rm -f "$t/hung"; touch "$t/hang"
	( run "$@" > /dev/null 2>&1 ) & bg=$!; disown "$bg" 2> /dev/null || true
	i=0; until [ -s "$t/hung" ]; do i=$((i + 1)); [ $i -gt 100 ] && { bad "the stuck run never reached nvram"; return 1; }; sleep 0.1; done
	stuck=$(cat "$t/hung"); rm -f "$t/hang"
}
age_note() {   # lock seconds: the run noted on the lock started that much earlier
	read -r p s a < "$TM/$1.run" 2> /dev/null || { bad "no note of the run that has the $1 lock"; return 0; }; echo "$p $((s - $2)) $a" > "$TM/$1.run"
}
gone_in() {   # pid seconds: wait for it to end
	i=0; while alive "$1"; do i=$((i + 1)); [ $i -gt $(($2 * 10)) ] && return 1; sleep 0.1; done; return 0
}

# 1. a stuck collect, but no older than a run can be: left alone
: > "$t/log"
start_stuck collect --once
held collect && ok "a collect stuck in nvram keeps the sampling lock" || bad "the lock isn't held"
run collect --once > /dev/null 2>&1 || true
alive "$stuck" && ok "young: the stuck run is left alone" || bad "young: it was stopped"
expect "young: nothing logged" "" "$(cat "$t/log")"

# 2. the same run, 6 minutes on: the next run stops it, logs it, and samples
age_note collect 360
rm -f "$R/www/user/wifiinsight/live.htm"
run collect --once > /dev/null 2>&1 || true
gone_in "$stuck" 5 && ok "stuck: the command it was stuck in is stopped" || bad "stuck: nvram is still there"
gone_in "$bg" 5 && ok "stuck: the run itself is stopped" || bad "stuck: the run is still there"
grep -q "^stopped a collect run stuck for 6 min, in: .*nvram get wl1_ifname$" "$t/log" && ok "stuck: logged, with what it was stuck in" || { bad "stuck: syslog"; sed 's/^/      | /' "$t/log"; }
read -r p s a < "$TM/collect.run" 2> /dev/null || true
[ "$a" = collect ] && [ "$p" != "$(cat "$t/hung")" ] && ok "stuck: the new run took the lock" || bad "stuck: collect.run is '$p $s $a'"
[ -s "$(find "$R" -name live.htm | head -1)" ] && ok "stuck: the new run carried on (live data written)" || bad "stuck: no live data"
held collect && bad "stuck: the lock is still taken" || ok "stuck: the lock is free again"

# 3. a command still holding the lock after its run is gone: stopped too
: > "$t/log"
start_stuck collect --once
for p in $(cat /proc/[0-9]*/stat 2>/dev/null | sed -n 's/^\([0-9]*\) (.*) [A-Za-z] \([0-9]*\) .*/\1 \2/p' | awk -v r="$bg" '{ pp[$1] = $2 } END { k[r] = 1; do { c = 0; for (p in pp) if (!(p in k) && (pp[p] in k)) { k[p] = 1; c = 1 } } while (c); for (p in k) print p }'); do
	[ "$p" = "$stuck" ] || kill -9 "$p" 2>/dev/null || true
done
gone_in "$bg" 5 || true; { wait "$bg"; } 2> /dev/null || true
alive "$stuck" && held collect && ok "orphan: nvram holds the lock after its run is gone" || bad "orphan: set-up"
age_note collect 360
run collect --once > /dev/null 2>&1 || true
gone_in "$stuck" 5 && ok "orphan: stopped" || bad "orphan: still there"
grep -q "nvram get wl1_ifname$" "$t/log" && ok "orphan: logged" || { bad "orphan: syslog"; sed 's/^/      | /' "$t/log"; }

# 4. a prune holding the lock for 10 minutes: never stopped; said once in 30 min
: > "$t/log"
exec 9> "$TM/collect.lock"; "$hflock" -n 9
echo "$$ $(( $(date +%s) - 600 )) prune" > "$TM/collect.run"; rm -f "$TM/collect.warned"
run collect --once > /dev/null 2>&1 || true
run collect --once > /dev/null 2>&1 || true
exec 9>&-
expect "prune: not stopped; the skipped run says so, once" "collect skipped: a prune run has had the collect lock for 10 min" "$(cat "$t/log")"

# 5. a stuck scan, 21 minutes on: the next scan stops it
: > "$t/log"
start_stuck scan
held scan && ok "a scan stuck in nvram keeps the scan lock" || bad "scan: the lock isn't held"
age_note scan 1260
run scan > /dev/null 2>&1 || true
gone_in "$stuck" 5 && gone_in "$bg" 5 && ok "scan: the stuck one is stopped" || bad "scan: still there"
grep -q "^stopped a scan run stuck for 21 min, in: .*nvram get wl1_ifname" "$t/log" && ok "scan: logged" || { bad "scan: syslog"; sed 's/^/      | /' "$t/log"; }
held scan && bad "scan: the lock is still taken" || ok "scan: the lock is free again"

# 6. status: sampling looks stuck when the last sample is over 10 minutes old
"$sqlite" "$D/wifiinsight.db" "DELETE FROM samples; INSERT INTO samples(ts, band) VALUES($(( $(date +%s) - 1500 )), '5g');"
out=$(run status 2>&1) || true
case "$out" in *"Sampling looks stuck: no new samples for 25 min."*) ok "status: says sampling looks stuck" ;; *) bad "status"; printf '%s\n' "$out" | sed 's/^/      | /' ;; esac
"$sqlite" "$D/wifiinsight.db" "INSERT INTO samples(ts, band) VALUES($(( $(date +%s) - 20 )), '5g');"
out=$(run status 2>&1) || true
case "$out" in *"looks stuck"*) bad "status: stuck while sampling" ;; *) ok "status: nothing said while sampling" ;; esac

[ $fail = 0 ] && echo "Stuck runs: all checks passed." || echo "Stuck runs: some checks failed."
exit $fail
