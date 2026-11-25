#!/bin/bash
# Regression test: the time axis' ticks fall on round local times in every time zone.
#
# Up to 2.3.0 the charts' time axis put its ticks wherever Chart.js's number steps fell: on 7D every 100000 s,
# labelled Tue 03h, Wed 06h, Thu 09h... with the range's two ends as the first and last. Now the page puts them
# at round times of the browser's clock: each midnight (7D), every 5th midnight (30D), every 3 h, 2 h, 10 min or
# 2 min of the day (1D, 12H, 1H, 10M). This runs the page's own timeTicks() and tickFmt() (taken from
# wifiinsight.asp) in every time zone the JavaScript engine knows, around every clock change in 2026 and 2027,
# and checks: ticks inside the range and in order; on round local times; days one (7D) or five (30D) apart,
# each at the start of a local day; labels to match; and how many (a day the clocks change has 23 or 25 hours).
# A time the clocks skip gets no tick, the hour they repeat gets its ticks twice (Cairo goes back at midnight).
#
# Usage: .github/tests/time-axis.sh [path/to/wifiinsight.asp]   (needs node 18 or later, with full ICU)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
page=${1:-$here/../../wifiinsight.asp}
command -v node > /dev/null || { echo "::error::time-axis.sh needs node"; exit 1; }
if node "$here/time-axis.js" "$page"; then echo "Time axis: all checks passed."; else echo "::error::Time axis: some checks failed."; exit 1; fi
