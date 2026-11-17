#!/bin/bash
# Regression test: on a router with Entware, the script still runs the firmware's own commands (BusyBox).
#
# A shell on the router (ssh, amtm, the README's install command) has Entware's folders first in its PATH.
# Up to 2.1.0 the script put them first too, so with Entware's coreutils installed, uname was GNU's, whose
# -o says GNU/Linux: the install took Asuswrt-Merlin for stock firmware (issue #30). And every run used
# GNU date, sort, sed... instead of the BusyBox ones it's written and tested for.
#
# The other suites run with ROOT set (a router laid out in a temporary folder), which leaves PATH alone,
# so this one takes the script's own PATH line and runs it as on a router: ROOT empty, PATH as Entware's
# profile sets it.
# Usage: .github/tests/entware-path.sh [path/to/wifiinsight.sh]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

line=$(grep -n '^\[ -z "\$ROOT" \] && PATH=' "$script" | head -1)
[ -n "$line" ] || { bad "the script's PATH line wasn't found"; exit 1; }
line=${line#*:}

for start in "/opt/bin:/opt/sbin:/bin:/usr/bin:/sbin:/usr/sbin" "/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin:/jffs/scripts"; do
	got=$(env -i ROOT= PATH="$start" /bin/sh -c "$line; echo \"\$PATH\"")
	# where each folder first comes
	pos() { echo "$got" | tr ':' '\n' | grep -n -x -- "$1" | head -1 | cut -d: -f1; }
	worst=0; for d in /sbin /bin /usr/sbin /usr/bin; do p=$(pos "$d"); [ -n "$p" ] && [ "$p" -gt "$worst" ] && worst=$p; done
	first_opt=999; for d in /opt/bin /opt/sbin; do p=$(pos "$d"); [ -n "$p" ] && [ "$p" -lt "$first_opt" ] && first_opt=$p; done
	if [ "$worst" -gt 0 ] && [ "$worst" -lt "$first_opt" ] && [ "$first_opt" != 999 ]; then
		ok "shell PATH $start: the firmware's folders first, Entware's after them"
	else
		bad "shell PATH $start: the script's PATH is $got"
	fi
done

[ $fail = 0 ] && echo "Entware PATH: all checks passed." || echo "Entware PATH: some checks failed."
exit $fail
