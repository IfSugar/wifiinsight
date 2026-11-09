#!/bin/bash
# Regression test: "update dev [branch]" installs a branch's newest code, and plain "update" stays on
# releases and brings a development version back to the latest release.
#
# A stand-in GitHub serves branches (commit lookup + raw files by commit) and releases. Each test
# build's "install" just copies itself into place (the real installer is what 'update' always runs).
# Runs with Merlin's BusyBox commands only, and [, printf and echo as separate programs.
# Usage: .github/tests/dev-update.sh [path/to/wifiinsight.sh]   (needs busybox)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
asp=$(dirname "$script")/wifiinsight.asp
bb=$(command -v busybox) || { echo "::error::dev-update.sh needs busybox installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
R=$t/root; F=$t/fix; GH=$t/github; A=$R/jffs/addons/wifiinsight
mkdir -p "$A" "$R/www/user" "$R/tmp" "$R/usr/sbin" "$F" "$GH/branches" "$t/bin"
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi; }

"$bb" --list > "$t/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$t/bb.list"; then ln -s "$bb" "$t/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$t/bin/$a"
	fi
done
rm -f "$t/bin/logger" "$t/bin/clear"
printf '#!%s sh\nshift 2; echo "$*" >> "%s/log"\n' "$bb" "$F" > "$t/bin/logger"
printf '#!/bin/sh\ncase "$2" in ntp_ready) echo 0 ;; esac\n' > "$t/bin/nvram"
printf '#!/bin/sh\nexit 1\n' > "$t/bin/wl"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/cru"
# Stand-in GitHub. $GH/branches/<name> holds a branch's commit; $GH/<commit or tag>/ its files;
# $GH/latest the latest release tag; $GH/api-down makes the API answer like a rate limit.
cat > "$t/bin/curl" <<EOF
#!$bb sh
out=""; fmt=""; url=""; accept=""
while [ \$# -gt 0 ]; do
	case "\$1" in -o) out=\$2; shift ;; -w) fmt=\$2; shift ;; -H) accept=\$2; shift ;; --retry|--connect-timeout|--max-time) shift ;; http*) url=\$1 ;; esac
	shift
done
case "\$url" in
	*api.github.com/*) [ -f "$GH/api-down" ] && { echo '{"message":"API rate limit exceeded"}'; exit 22; } ;;
esac
case "\$url" in
	*api.github.com/repos/*/commits/*)
		b=\${url##*/commits/}; [ -f "$GH/branches/\$b" ] || exit 22
		cat "$GH/branches/\$b"; exit 0 ;;
	*api.github.com/repos/*/releases/latest)
		[ -f "$GH/latest" ] || exit 22; printf '{"tag_name": "%s"}' "\$(cat "$GH/latest")"; exit 0 ;;
	*/releases/latest) [ -f "$GH/latest" ] || exit 22; [ "\$fmt" = '%{redirect_url}' ] && printf 'https://github.com/x/y/releases/tag/%s' "\$(cat "$GH/latest")"; exit 0 ;;
	https://raw.githubusercontent.com/IfSugar/wifiinsight/*)
		f="$GH/\${url#https://raw.githubusercontent.com/IfSugar/wifiinsight/}"
		if [ -f "\$f" ]; then [ -n "\$out" ] && cp "\$f" "\$out"; [ "\$fmt" = '%{http_code}' ] && printf 200; exit 0; fi
		[ "\$fmt" = '%{http_code}' ] && printf 404; exit 0 ;;
esac
exit 6
EOF
chmod +x "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl" "$t/bin/cru" "$t/bin/curl"

# A build of the current files with another version and a label; its "install" copies itself in.
build() {   # dir version label
	mkdir -p "$1"
	sed "s/^VERSION=\"[0-9.]*\"/VERSION=\"$2\"/" "$script" > "$1/wifiinsight.sh"
	sed "s/wifiinsight-version: [0-9.]* /wifiinsight-version: $2 /" "$asp" > "$1/wifiinsight.asp"
	printf '# test build: %s\n' "$3" >> "$1/wifiinsight.sh"
	sed -i 's|^	install)       install ;;|	install)       cp "$0" "$SCRIPT.new" \&\& mv -f "$SCRIPT.new" "$SCRIPT"; exit 0 ;;|' "$1/wifiinsight.sh"
	grep -q 'SCRIPT.new" && mv' "$1/wifiinsight.sh" || { echo "::error::couldn't build a test version"; exit 1; }
}
branch() {   # name commit version
	build "$GH/$2" "$3" "branch $1"; mkdir -p "$(dirname "$GH/branches/$1")"; printf '%s' "$2" > "$GH/branches/$1"
	mkdir -p "$GH/$1"; cp "$GH/$2/"* "$GH/$1/"   # raw files by branch name too (the fallback)
}
release() { build "$GH/$1" "$1" "release $1"; echo "$1" > "$GH/latest"; }
reset_install() {
	cp "$script" "$A/wifiinsight.sh"; cp "$asp" "$A/wifiinsight.asp"
	printf 'COLLECTION=on\nAMTM_UPDATE=on\nDATA_DIR="%s"\nSQLITE="/nonexistent"\n' "$t/data" > "$A/config"
	rm -f "$A/build" "$GH/api-down"; : > "$F/log"
}
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$A/wifiinsight.sh" "$@"; }
label() { sed -n 's/^# test build: //p' "$A/wifiinsight.sh"; }
buildfile() { cut -d' ' -f1-3 "$A/build" 2>/dev/null || echo none; }
ver=$(sed -n 's/^VERSION="\([0-9][0-9.]*\)".*/\1/p' "$script" | head -1)
C1=1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d; C2=9f8e7d6c5b4a39281706f5e4d3c2b1a0f9e8d7c6

branch main "$C1" "$ver"; branch feature/x "$C2" "$ver"; release "$ver"

# ---- update dev -------------------------------------------------------------------------------------
reset_install
rc=0; out=$(run update dev 2>&1) || rc=$?
expect "update dev: installs main at its newest commit" "0|branch main|dev main 1a2b3c4" "$rc|$(label)|$(buildfile)"
case "$(run status 2>&1 | head -1)" in "WiFi Insight $ver (development version: main @ 1a2b3c4, installed "*) ok "status says it's a development version" ;;
	*) bad "status first line: $(run status 2>&1 | head -1)" ;; esac
grep -q 'development version installed: main @ 1a2b3c4' "$F/log" && ok "update dev: logged" || bad "update dev: no syslog line"

reset_install
rc=0; run update dev feature/x > /dev/null 2>&1 || rc=$?
expect "update dev <branch>: another branch" "0|branch feature/x|dev feature/x 9f8e7d6" "$rc|$(label)|$(buildfile)"

reset_install; touch "$GH/api-down"
rc=0; out=$(run update dev 2>&1) || rc=$?
expect "update dev, GitHub API down: falls back to the branch's files" "0|branch main|dev main unknown" "$rc|$(label)|$(buildfile)"
case "$out" in *"may be up to 5 minutes old"*) ok "update dev, API down: says the files may be a few minutes old" ;; *) bad "API-down note missing" ;; esac

for b in 'main;reboot' '../etc' '-x' 'a b' 'main..x' 'x$(id)'; do
	reset_install
	rc=0; out=$(run update dev "$b" 2>&1) || rc=$?
	case "$out" in *"isn't a branch name; nothing was changed."*) said=refused ;; *) said="$out" ;; esac
	expect "update dev '$b': refused before asking GitHub, nothing changed" "1|refused||none" "$rc|$said|$(label)|$(buildfile)"
done
reset_install
rc=0; out=$(run update dev nosuch 2>&1) || rc=$?
expect "update dev to a branch that doesn't exist: nothing changed" "1||none" "$rc|$(label)|$(buildfile)"
case "$out" in *"no such branch, or no connection to GitHub"*) ok "missing branch: says why" ;; *) bad "missing branch message: $out" ;; esac

reset_install; branch broken 0000000000000000000000000000000000000001 "$ver"
sed -i "s/wifiinsight-version: [0-9.]* /wifiinsight-version: 0.0.1 /" "$GH/0000000000000000000000000000000000000001/wifiinsight.asp"
rc=0; out=$(run update dev broken 2>&1) || rc=$?
expect "update dev with a page from another version: refused" "1||none" "$rc|$(label)|$(buildfile)"

# ---- plain update stays on releases ---------------------------------------------------------------------
reset_install; run update dev > /dev/null 2>&1
rc=0; out=$(run update 2>&1) || rc=$?
expect "update from a development version, release has the same number: installs the release" "0|release $ver|none" "$rc|$(label)|$(buildfile)"
rc=0; out=$(run update 2>&1) || rc=$?
case "$out" in *"Already up to date ($ver)."*) ok "update on the release: already up to date" ;; *) bad "update on the release: $out" ;; esac

reset_install; branch main "$C1" 9.9.9; release 9.9.8; run update dev > /dev/null 2>&1
rc=0; out=$(run update 2>&1) || rc=$?
expect "update from a newer development version: keeps it" "0|branch main|dev main 1a2b3c4" "$rc|$(label)|$(buildfile)"
case "$out" in *"This is 9.9.9 (a development version), newer than the latest release (9.9.8)"*) ok "...and says so" ;; *) bad "newer dev message: $out" ;; esac
rc=0; run update force > /dev/null 2>&1 || rc=$?
expect "update force: back to the release" "0|release 9.9.8|none" "$rc|$(label)|$(buildfile)"

# ---- the menu -----------------------------------------------------------------------------------------
reset_install; branch main "$C1" "$ver"
printf '8\n\n\ne\n' | run menu > "$t/menu.out" 2>&1 || true
expect "menu option 8, Enter for main: installs the development version" "branch main|dev main 1a2b3c4" "$(label)|$(buildfile)"
grep -q 'This is a development version: main @ 1a2b3c4' "$t/menu.out" && ok "menu: restarts in the new script, which says it's a development version" || { bad "menu after the dev update"; tail -25 "$t/menu.out" | sed 's/^/      | /'; }
reset_install
printf '8\ne\ne\n' | run menu > /dev/null 2>&1 || true
expect "menu option 8, e: goes back, nothing changed" "|none" "$(label)|$(buildfile)"

[ $fail -eq 0 ] && echo "Development updates: all checks passed." || { echo "::error::Development updates: some checks failed."; exit 1; }
