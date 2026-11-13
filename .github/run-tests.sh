#!/bin/bash
# Runs every suite in .github/tests at once: they're independent, each in its own temporary folder with
# its own stand-ins and clock. Then prints each one's output in order (grouped on GitHub) and a summary,
# and exits 1 if any failed. The slowest suites start first, so they don't finish last.
# Usage: .github/run-tests.sh [jobs]   (default: the number of CPUs, at least 2)
set -u
here=$(cd "$(dirname "$0")" && pwd)
jobs=${1:-$(nproc 2>/dev/null || echo 2)}; [ "$jobs" -ge 2 ] 2>/dev/null || jobs=2
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
slow="trickle one-channel multi-radio quiet-hours short-scans scan-wait measured repair large-history"
all=$(cd "$here/tests" && ls *.sh | sed 's/\.sh$//')
order=$(for n in $slow; do [ -f "$here/tests/$n.sh" ] && echo "$n"; done; for n in $all; do case " $slow " in *" $n "*) ;; *) echo "$n" ;; esac; done)

start=$(date +%s)
for n in $order; do
	while [ "$(jobs -rp | wc -l)" -ge "$jobs" ]; do wait -n; done
	( s=$(date +%s); bash "$here/tests/$n.sh" > "$out/$n.log" 2>&1; echo "$? $(( $(date +%s) - s ))" > "$out/$n.rc" ) &
done
wait

fail=0; gh=${GITHUB_ACTIONS:-}
for n in $all; do
	read -r rc secs < "$out/$n.rc" || { rc=1; secs=?; }
	if [ -n "$gh" ]; then echo "::group::$n ($secs s)"; else echo "===== $n ($secs s)"; fi
	cat "$out/$n.log"
	[ -n "$gh" ] && echo "::endgroup::"
	if [ "$rc" != 0 ]; then fail=1; [ -n "$gh" ] && echo "::error::$n failed (exit $rc)"; fi
done
echo
echo "$(echo "$all" | wc -l) suites in $(( $(date +%s) - start )) s, $jobs at a time:"
for n in $all; do read -r rc secs < "$out/$n.rc"; printf '  %-5s %-16s %4s s\n' "$([ "$rc" = 0 ] && echo ok || echo FAIL)" "$n" "$secs"; done
exit $fail
