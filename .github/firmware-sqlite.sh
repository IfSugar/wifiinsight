#!/bin/sh
# Builds the sqlite3 that Asuswrt-Merlin ships as /usr/sbin/sqlite3, from the Merlin source at a pinned
# commit (each file checked by its sha256), with the firmware's flags: release/src/router/Makefile runs
# sqlite's configure with --enable-threadsafe --disable-dynamic-extensions, its configure.ac adds FTS4,
# FTS5, JSON1 and RTREE, and its Makefile.am builds the shell with the DBPAGE, STMT and DBSTAT tables.
#   3.25.3: Merlin 386.1 to 3004.388.4 (here 386.11)      3.42.0: 3004.388.6 and later, 3006.102
# Usage: .github/firmware-sqlite.sh 3.25.3|3.42.0 outdir   ->   outdir/sqlite3
set -eu
ver=$1; out=$2
case "$ver" in
	3.25.3) commit=7fee45c7d1aaf78b477bde952dccc98b14fbc5b3
		sums="c7c20dfd5e314e20785a1bc52a55876963d14f7573bffac4cc4f2d7f77993f78 sqlite3.c
02569e70de38d01d90a26a478a57582372a4330efd25ad5c2af650d88a395b34 shell.c
d42151d2e04865fb5d79936f178042ffbcb7a704449de17f09ed5c2a1d58a13f sqlite3.h
aed0569d388fd0116ed4afe9f3d453986af675f8e96913380b576f2b1187c09e sqlite3ext.h" ;;
	3.42.0) commit=2c4d3ee043bd1c714c341d75a9efa8e77c2955b9
		sums="d6fd08f425763673846a6b7f3635c1e73d8d66d575585460c9bf62ea814f1230 sqlite3.c
c4231eae8d4b49310e4bdb3a4f8b96e4493f2cb9915a9c9355681125b7766e0d shell.c
1184605a375f9ccabd6efb340a3b82baf5bdd0aa1ba77e7132df35c58839b5d4 sqlite3.h
cf9785762f8801049b841f873cdeecfa2780b0f6465e2b76f72d2c10384cf7ce sqlite3ext.h" ;;
	*) echo "Unknown version $ver (3.25.3 or 3.42.0)" >&2; exit 1 ;;
esac
src="$out/src"; mkdir -p "$src"
for f in sqlite3.c shell.c sqlite3.h sqlite3ext.h; do
	curl -fsSL --retry 3 -o "$src/$f" "https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/$commit/release/src/router/sqlite/$f"
done
(cd "$src" && printf '%s\n' "$sums" | sed 's/ /  /' | sha256sum -c --quiet)
gcc -O1 -w -D_REENTRANT=1 -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION=1 \
	-DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE \
	-DSQLITE_ENABLE_EXPLAIN_COMMENTS -DSQLITE_ENABLE_DBPAGE_VTAB -DSQLITE_ENABLE_STMTVTAB -DSQLITE_ENABLE_DBSTAT_VTAB \
	-I"$src" "$src/shell.c" "$src/sqlite3.c" -lpthread -ldl -lm -o "$out/sqlite3"
"$out/sqlite3" -version
