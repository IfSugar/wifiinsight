#!/bin/bash
# Regression test: WiFi Insight works the way amtm (the Asuswrt-Merlin Terminal Menu) expects.
#
#  1. amtm reads the installed and the released version with its own grep; it must find VERSION.
#  2. "amtmupdate check" exits 0, or 1 when the user turned amtm updates off.
#  3. "amtmupdate" updates to the latest release with two lines of output, exit 0; a failed update
#     exits 1 and leaves the installed script alone. A stand-in GitHub serves the releases.
#  4. Run with no arguments outside a terminal, it prints the usage (cron, scripts); "menu" shows
#     the menu, and its options change the collection mode (config, saved settings, cron) and the
#     amtm switch.
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs.
# Usage: .github/tests/amtm.sh [path/to/wifiinsight.sh]   (needs busybox)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
asp=$(dirname "$script")/wifiinsight.asp
bb=$(command -v busybox) || { echo "::error::amtm.sh needs busybox installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
R=$t/root; F=$t/fix; GH=$t/github
A=$R/jffs/addons/wifiinsight
mkdir -p "$A" "$R/jffs/scripts" "$R/www/user" "$R/tmp" "$R/usr/sbin" "$F" "$GH" "$t/bin"
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }

ver=$(sed -n 's/^VERSION="\([0-9][0-9.]*\)".*/\1/p' "$script" | head -1)

# ---- 1: amtm's version check (amtm.mod script_check: scriptgrep, then this regex) -------------
amtm_ver=$(grep '^VERSION=' "$script" | grep -m1 -oE '[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})' || true)
expect "amtm reads the version as $ver" "$ver" "$amtm_ver"

# ---- the stand-in router -------------------------------------------------------------------------
"$bb" --list > "$t/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$t/bb.list"; then ln -s "$bb" "$t/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$t/bin/$a"
	fi
done
rm -f "$t/bin/logger" "$t/bin/clear"
printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$F" > "$t/bin/logger"
cat > "$t/bin/nvram" <<'EOF'
#!/bin/sh
case "$2" in ntp_ready) echo 0 ;; wl0_ifname) echo eth6 ;; wl1_ifname) echo eth7 ;; esac
EOF
printf '#!/bin/sh\nexit 1\n' > "$t/bin/wl"
cat > "$t/bin/cru" <<EOF
#!/bin/sh
f="$F/crontab"; touch "\$f"
case "\$1" in
	a) grep -v "#\$2#\\\$" "\$f" > "\$f.n"; echo "\$3 #\$2#" >> "\$f.n"; mv "\$f.n" "\$f" ;;
	d) grep -v "#\$2#\\\$" "\$f" > "\$f.n"; mv "\$f.n" "\$f" ;;
	l) cat "\$f" ;;
esac
EOF
cat > "$R/usr/sbin/helper.sh" <<EOF
am_settings_get() { sed -n "s/^\$1 //p" "$F/settings"; }
am_settings_set() { touch "$F/settings"; sed -i "/^\$1 /d" "$F/settings"; echo "\$1 \$2" >> "$F/settings"; }
EOF
# Stand-in GitHub: the releases API, the releases/latest redirect and raw files of each tag, from $GH.
# $GH/latest holds the latest tag; $GH/<tag>/ holds that tag's files.
cat > "$t/bin/curl" <<EOF
#!$bb sh
out=""; fmt=""; url=""
while [ \$# -gt 0 ]; do
	case "\$1" in -o) out=\$2; shift ;; -w) fmt=\$2; shift ;; -H|--retry|--connect-timeout|--max-time) shift ;; http*) url=\$1 ;; esac
	shift
done
tag=\$(cat "$GH/latest" 2>/dev/null)
case "\$url" in
	*api.github.com/repos/*/releases/latest)
		[ -n "\$tag" ] || exit 22
		body="{\"tag_name\": \"\$tag\"}" ;;
	*/releases/latest) [ -n "\$tag" ] || exit 22; [ "\$fmt" = '%{redirect_url}' ] && printf 'https://github.com/x/y/releases/tag/%s' "\$tag"; exit 0 ;;
	https://raw.githubusercontent.com/IfSugar/wifiinsight/*)
		f="$GH/\${url#https://raw.githubusercontent.com/IfSugar/wifiinsight/}"
		if [ -f "\$f" ]; then [ -n "\$out" ] && cp "\$f" "\$out"; [ "\$fmt" = '%{http_code}' ] && printf 200; exit 0; fi
		[ "\$fmt" = '%{http_code}' ] && printf 404; exit 0 ;;
	*) exit 6 ;;
esac
if [ -n "\$out" ]; then printf '%s' "\$body" > "\$out"; else printf '%s' "\$body"; fi
[ "\$fmt" = '%{http_code}' ] && printf 200
exit 0
EOF
chmod +x "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl" "$t/bin/cru" "$t/bin/curl"
CONF=$A/config
reset_install() {   # the current script, installed, with a config from before 1.2.0
	cp "$script" "$A/wifiinsight.sh"; cp "$asp" "$A/wifiinsight.asp"
	printf 'SAMPLE_INTERVAL=30\nSCAN_INTERVAL=30\nRETAIN_DAYS=30\nCOLLECTION=on\nDATA_DIR="%s"\nSQLITE="/nonexistent"\n' "$t/data" > "$CONF"
	: > "$F/log"; : > "$F/crontab"; rm -f "$F/settings"
}
# A release: the current files with another version number. Its installer just puts itself in place
# (the real one is the same install that 'update' always runs); FAIL_INSTALL makes it fail.
release() {   # tag [broken]
	mkdir -p "$GH/$1"
	sed "s/^VERSION=\"[0-9.]*\"/VERSION=\"$1\"/" "$script" > "$GH/$1/wifiinsight.sh"
	sed "s/wifiinsight-version: [0-9.]* /wifiinsight-version: $1 /" "$asp" > "$GH/$1/wifiinsight.asp"
	cat >> "$GH/$1/wifiinsight.sh" <<'EOF'
# test release: "install" only copies itself into place
EOF
	sed -i 's|^	install)       install ;;|	install)       [ -n "$FAIL_INSTALL" ] \&\& die "Nothing was installed or changed."; cp "$0" "$SCRIPT.new" \&\& mv -f "$SCRIPT.new" "$SCRIPT"; exit 0 ;;|' "$GH/$1/wifiinsight.sh"
	grep -q 'FAIL_INSTALL' "$GH/$1/wifiinsight.sh" || { echo "::error::couldn't build the test release"; exit 1; }
	echo "$1" > "$GH/latest"
}
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$A/wifiinsight.sh" "$@"; }
installed_ver() { sed -n 's/^VERSION="\([0-9][0-9.]*\)".*/\1/p' "$A/wifiinsight.sh" | head -1; }

# ---- 2: amtmupdate check ----------------------------------------------------------------------------
reset_install
rc=0; out=$(run amtmupdate check 2>&1) || rc=$?
expect "amtmupdate check: enabled by default (exit 0, quiet)" "0|" "$rc|$out"
echo 'AMTM_UPDATE=off' >> "$CONF"
rc=0; run amtmupdate check > /dev/null 2>&1 || rc=$?
expect "amtmupdate check: AMTM_UPDATE=off exits 1" "1" "$rc"
rc=0; out=$(run amtmupdate 2>&1) || rc=$?
expect "amtmupdate when turned off: refuses, exit 1" "1" "$rc"
expect "amtmupdate when turned off: installed script untouched" "$ver" "$(installed_ver)"
reset_install; echo 'AMTM_UPDATE=maybe' >> "$CONF"
rc=0; run amtmupdate check > /dev/null 2>&1 || rc=$?
expect "amtmupdate check: an unknown AMTM_UPDATE value means on" "0" "$rc"

# ---- 3: amtmupdate -------------------------------------------------------------------------------------
reset_install; release 9.9.9
rc=0; out=$(run amtmupdate 2>&1) || rc=$?
expect "amtmupdate to a newer release: exit 0" "0" "$rc"
expect "amtmupdate to a newer release: two lines, like Diversion's" \
	"$(printf '  i  Running function amtmupdate\n  ✔  WiFi Insight 9.9.9 amtmupdate complete')" "$out"
expect "amtmupdate to a newer release: installed" "9.9.9" "$(installed_ver)"
expect "amtmupdate to a newer release: installed script is the release file, so amtm's MD5 check matches" \
	"$(md5sum < "$GH/9.9.9/wifiinsight.sh")" "$(md5sum < "$A/wifiinsight.sh")"
grep -q "amtmupdate: $ver -> 9.9.9" "$F/log" && ok "amtmupdate: logged to syslog" || bad "amtmupdate: no syslog line"

reset_install; release 9.9.10; rm "$GH/9.9.10/wifiinsight.asp"
rc=0; out=$(run amtmupdate 2>&1) || rc=$?
expect "amtmupdate when the page can't be downloaded: exit 1" "1" "$rc"
case "$out" in *"amtmupdate failed: Couldn't download the matching web page; nothing was changed."*) ok "amtmupdate failure: says why in one line" ;;
	*) bad "amtmupdate failure message"; echo "$out" | sed 's/^/      | /' ;; esac
expect "amtmupdate failure: still two lines" "2" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
expect "amtmupdate failure: installed script untouched" "$ver" "$(installed_ver)"

reset_install; release 9.9.11
rc=0; out=$(FAIL_INSTALL=1 run amtmupdate 2>&1) || rc=$?
expect "amtmupdate when the installer refuses: exit 1" "1" "$rc"
expect "amtmupdate when the installer refuses: installed script untouched" "$ver" "$(installed_ver)"

reset_install; rm -f "$GH/latest"
rc=0; out=$(run amtmupdate 2>&1) || rc=$?
expect "amtmupdate without GitHub: exit 1" "1" "$rc"

# ---- 4: no arguments, the menu and the collection switch ---------------------------------------------
reset_install
out=$(run < /dev/null 2>&1 | head -1)
case "$out" in "Usage: "*) ok "no arguments outside a terminal: prints the usage" ;; *) bad "no arguments outside a terminal: '$out'" ;; esac
rc=0; out=$(printf 'e\n' | run menu 2>&1) || rc=$?
case "$out" in *"WiFi Insight $ver"*"1  Status"*"9  Uninstall"*) ok "menu: shows the options" ;; *) bad "menu output"; echo "$out" | sed 's/^/      | /' ;; esac
expect "menu: e exits 0" "0" "$rc"
printf '3\n2\n\ne\n' | run menu > "$t/menu.out" 2>&1 || true
expect "menu, collection, scans paused: config" "COLLECTION=paused" "$(grep -o '^COLLECTION=[a-z]*' "$CONF")"
expect "menu, collection, scans paused: saved like the page saves it" "wifiinsight_mode paused" "$(cat "$F/settings" 2>/dev/null)"
expect "menu, collection, scans paused: no scan job" "collect prune" "$(sed -n 's/.*#wifiinsight_\(.*\)#$/\1/p' "$F/crontab" | sort | tr '\n' ' ' | sed 's/ $//')"
printf '7\ne\n' | run menu > /dev/null 2>&1 || true
expect "menu, option 7: turns amtm updates off" "AMTM_UPDATE=off" "$(grep -o '^AMTM_UPDATE=[a-z]*' "$CONF")"
printf '7\ne\n' | run menu > /dev/null 2>&1 || true
expect "menu, option 7 again: back on" "AMTM_UPDATE=on" "$(grep -o '^AMTM_UPDATE=[a-z]*' "$CONF")"
printf '9\nno\n\ne\n' | run menu > /dev/null 2>&1 || true
[ -f "$A/wifiinsight.sh" ] && ok "menu, uninstall without typing yes: nothing removed" || bad "menu uninstall removed without confirmation"
run collection off > /dev/null 2>&1
expect "collection off: no cron jobs" "" "$(cat "$F/crontab")"
rc=0; run collection sometimes > /dev/null 2>&1 || rc=$?
expect "collection with a wrong value: refused" "1|COLLECTION=off" "$rc|$(grep -o '^COLLECTION=[a-z]*' "$CONF")"

[ $fail -eq 0 ] && echo "amtm: all checks passed." || { echo "::error::amtm: some checks failed."; exit 1; }
