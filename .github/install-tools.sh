#!/bin/sh
# busybox and sqlite3 for the checks. Their packages are kept in ~/debs, which the workflow keeps in the
# Actions cache: installing them from there takes a second, while apt took anything from 10 to 90 s (a slow
# mirror). When the cached ones are missing or don't install (a newer runner image, say), they come from apt
# again, and ~/debs is filled for the next run.
d=$HOME/debs
if ls "$d"/*.deb > /dev/null 2>&1 && sudo dpkg -i "$d"/*.deb > /dev/null 2>&1 \
	&& busybox true 2> /dev/null && sqlite3 -version > /dev/null 2>&1; then
	echo "busybox and sqlite3: from the cache"; exit 0
fi
rm -rf "$d"; mkdir -p "$d"
fetch() { (cd "$d" && apt-get download busybox sqlite3 > /dev/null 2>&1); }
fetch || { sudo apt-get update -qq; fetch; } || true
if ! { ls "$d"/*.deb > /dev/null 2>&1 && sudo dpkg -i "$d"/*.deb > /dev/null 2>&1; }; then
	rm -rf "$d"   # nothing worth keeping: this run installs them the usual way
	sudo apt-get install -y -qq --no-install-recommends busybox sqlite3 > /dev/null 2>&1 \
		|| { sudo apt-get update -qq && sudo apt-get install -y -qq --no-install-recommends busybox sqlite3 > /dev/null; }
fi
busybox true && sqlite3 -version > /dev/null || { echo "::error::Couldn't install busybox and sqlite3"; exit 1; }
echo "busybox and sqlite3: from apt"
