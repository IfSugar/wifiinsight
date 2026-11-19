#!/bin/sh
# busybox and sqlite3 for the checks. apt took anything from 10 to 90 s a job (a slow mirror), as long as the
# suites themselves, so the packages it downloads are kept in ~/debs, which the workflow keeps in the Actions
# cache (one per runner image version): from there they install in a second. When they're missing or don't
# install, apt installs them as before, downloading into ~/debs for the next run.
d=$HOME/debs
have() { busybox true 2> /dev/null && sqlite3 -version > /dev/null 2>&1; }
if ls "$d"/*.deb > /dev/null 2>&1 && sudo dpkg -i "$d"/*.deb > /dev/null 2>&1 && have; then
	echo "busybox and sqlite3: from the cache"; exit 0
fi
rm -rf "$d"; mkdir -p "$d/partial"
inst() {   # with what they depend on, keeping what's downloaded in $d
	sudo apt-get install -y -qq --no-install-recommends -o Dir::Cache::Archives="$d" -o APT::Keep-Downloaded-Packages=true \
		busybox sqlite3 > /dev/null 2>&1
}
inst || { sudo apt-get update -qq && inst; } || { echo "::error::Couldn't install busybox and sqlite3"; exit 1; }
sudo rm -rf "$d/partial" "$d/lock"
have || { echo "::error::busybox or sqlite3 doesn't run"; exit 1; }
echo "busybox and sqlite3: from apt ($(ls "$d"/*.deb 2> /dev/null | wc -l) packages kept for the next run)"
