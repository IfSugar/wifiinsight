#!/bin/bash
# Regression test: an old copy of the script hands over to the installed one.
#
# The install command downloads to /tmp/wifiinsight.sh, and that copy stays until a reboot. A user on
# 1.3.0 ran the 1.2.0 copy left there ('sh /tmp/wifiinsight.sh scan'), got 1.2.0's behaviour and took it
# for 1.3.0's. Now a copy whose version differs from the installed one says so and runs the installed
# script instead, except for install, update, uninstall, check and version. (install also deletes the
# downloaded /tmp copy when it's done.)
#
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs.
# Usage: .github/tests/old-copy.sh [path/to/wifiinsight.sh]   (needs busybox, sqlite3)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::old-copy.sh needs busybox installed"; exit 1; }
sqlite=$(command -v sqlite3) || { echo "::error::old-copy.sh needs sqlite3 installed"; exit 1; }
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
awk '/^init_db\(\) \{/ { f = 1 } f && /^EOF$/ { exit } f && p { print } f && /<<.EOF.$/ { p = 1 }' "$script" > "$t/schema.sql"
"$sqlite" "$D/wifiinsight.db" < "$t/schema.sql"
run() { f=$1; shift; WI_ROOT="$R" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$f" "$@" 2>&1 || true; }

V=$(sed -n 's/^VERSION="\([0-9][0-9.]*\)".*/\1/p' "$script" | head -1)
INSTALLED=$R/jffs/addons/wifiinsight/wifiinsight.sh
OLD=$R/tmp/wifiinsight.sh                                    # what the install command left behind
sed 's/^VERSION=".*"/VERSION="1.2.0"/' "$script" > "$OLD"
cp "$script" "$t/same.sh"                                    # a copy of the installed version, elsewhere

# 1: the old copy hands over to the installed script
out=$(run "$OLD" status)
has "old copy: says so" "This is WiFi Insight 1.2.0 at $OLD, but $V is installed: running that instead." "$out"
has "old copy: the installed script ran" "WiFi Insight $V" "$out"
hasnt "old copy: its own status didn't run" "WiFi Insight 1.2.0" "$(printf '%s\n' "$out" | grep -v '^This is WiFi Insight')"

# 2: ...except for the commands that are about the copy itself (install, update and uninstall aren't
# run here: they'd change the test's install; the same line of the script lists them)
expect "old copy: 'version' is its own" "1.2.0" "$(run "$OLD" version)"
hasnt "old copy: 'check' isn't handed over" "running that instead" "$(run "$OLD" check)"
grep -q '^	install|update|uninstall|check|version) ;;$' "$script" && ok "old copy: install, update, uninstall, check and version are exempt" || bad "the exemption list changed"

# 3: no hand-over from the installed script, or from a copy of the same version
hasnt "installed script: runs as is" "running that instead" "$(run "$INSTALLED" status)"
hasnt "same version elsewhere: runs as is" "running that instead" "$(run "$t/same.sh" status)"

# 4: nothing installed: a copy just runs
mv "$INSTALLED" "$INSTALLED.away"
hasnt "nothing installed: runs as is" "running that instead" "$(run "$OLD" status)"
mv "$INSTALLED.away" "$INSTALLED"

[ $fail -eq 0 ] && echo "Old copies: all checks passed." || { echo "::error::Old copies: some checks failed."; exit 1; }
