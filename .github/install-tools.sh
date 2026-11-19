#!/bin/sh
# busybox and sqlite3 for the checks. Installing them with apt took anything from 10 to 100 s a job: right
# after boot, the runner's own package updates hold dpkg's lock, and apt waits for it. So a tool the runner
# image lacks is taken from its package without installing it: unpacked into ~/tools/x (dpkg-deb needs no
# lock), linked into ~/tools/bin, which goes first in PATH for the later steps (GITHUB_PATH). The package
# is kept in ~/debs, which the workflow keeps in the Actions cache, so the next run doesn't download it.
# Only if that doesn't give a working tool does apt install it, as before.
d=$HOME/debs; t=$HOME/tools
mkdir -p "$d" "$t/bin"; PATH="$t/bin:$PATH"
works() { case "$1" in busybox) busybox true 2> /dev/null ;; sqlite3) sqlite3 -version > /dev/null 2>&1 ;; esac; }
for p in busybox sqlite3; do
	works "$p" && { echo "$p: on the runner image"; continue; }
	if ! ls "$d/${p}"_*.deb > /dev/null 2>&1; then
		( cd "$d" && { apt-get download "$p" > /dev/null 2>&1 || { sudo apt-get update -qq && apt-get download "$p" > /dev/null 2>&1; }; } )
		from=downloaded
	else
		from="from the cache"
	fi
	f=$(ls "$d/${p}"_*.deb 2> /dev/null | head -1)
	if [ -n "$f" ] && dpkg-deb -x "$f" "$t/x" 2> /dev/null && b=$(find "$t/x" -type f -name "$p" -perm -100 | head -1) && [ -n "$b" ]; then
		ln -sf "$b" "$t/bin/$p"
	fi
	if works "$p"; then
		echo "$p: unpacked, $from ($(basename "$f"))"
	else
		rm -f "$t/bin/$p" "$d/${p}"_*.deb
		sudo apt-get install -y -qq --no-install-recommends "$p" > /dev/null 2>&1 \
			|| { sudo apt-get update -qq && sudo apt-get install -y -qq --no-install-recommends "$p" > /dev/null; }
		works "$p" || { echo "::error::Couldn't install $p"; exit 1; }
		echo "$p: installed with apt"
	fi
done
[ -n "$GITHUB_PATH" ] && echo "$t/bin" >> "$GITHUB_PATH"
exit 0
