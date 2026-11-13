#!/bin/bash
# Regression test for quiet hours and the collection switch (1.1.0).
#
#  1. The page and the script read the quiet hours mask the same way: the page's own encoder
#     (taken from wifiinsight.asp) builds masks, and the script's quiet_at must agree on every
#     half hour of the week, with BusyBox awk like on the router.
#  2. The script's summary of the mask (status) matches the page's.
#  3. Saving from the page (service_event -> apply_settings) writes the config, sets the cron jobs
#     for each collection mode, and ignores values that aren't valid.
#  4. A scheduled scan does nothing in quiet hours, paused or off; collect does nothing when off.
#  5. A hand-edited config with a bad QUIET or COLLECTION is ignored, and status says so.
#
# Runs the script with only Merlin's BusyBox commands, and with [, printf and echo as separate
# programs, like large-history.sh.
#
# Usage: .github/tests/quiet-hours.sh [path/to/wifiinsight.sh]   (needs busybox and node)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../../wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
asp=$(dirname "$script")/wifiinsight.asp
bb=$(command -v busybox) || { echo "::error::quiet-hours.sh needs busybox installed"; exit 1; }
node=$(command -v node) || { echo "::error::quiet-hours.sh needs node installed"; exit 1; }
bash_bin=$(command -v bash)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

# ---- 1 + 2: page encoder vs the script's reader, on every half hour -------------------------
mkdir -p "$t/awkbin"; ln -s "$bb" "$t/awkbin/awk"
sed -n '/^quiet_at() {/,/^}/p; /^quiet_text() {/,/^}/p' "$script" > "$t/q.sh"
grep -q '^quiet_at() {' "$t/q.sh" && grep -q '^quiet_text() {' "$t/q.sh" || { echo "::error::couldn't find quiet_at/quiet_text in the script"; exit 1; }

# Masks from the page's own code: its presets, plus random ones. Each line: mask, page summary
# (as the script would write it: ASCII dashes, "; " between days), then the 336 bits.
"$node" - "$asp" > "$t/masks.txt" <<'EOF'
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
function grab(name) {   // a function or var [...] from the page, by brace matching
  let i = src.indexOf('function ' + name + '('), isVar = false;
  if (i < 0) { i = src.indexOf('var ' + name + ' = ['); isVar = true; }
  if (i < 0) throw new Error('page has no ' + name);
  const open = isVar ? '[' : '{', close = isVar ? ']' : '}';
  let k = src.indexOf(open, i), depth = 0, str = null;
  for (; k < src.length; k++) {
    const c = src[k];
    if (str) { if (c === '\\') k++; else if (c === str) str = null; continue; }
    if (c === "'" || c === '"') str = c;
    else if (c === open) depth++;
    else if (c === close && --depth === 0) break;
  }
  return src.slice(i, k + 1) + (isVar ? ';' : '') + '\n';
}
const code = ['QPRESETS', 'qEncode', 'qDecode', 'qText', 'qDayRanges', 'slotHm', 'pad'].map(grab).join('');
const run = new Function(code + `
  var QD = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], out = [], seed = 7;
  function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }
  var masks = QPRESETS.map(function (p) { var a = []; for (var i = 0; i < 336; i++) a.push(!!p[1](Math.floor(i / 48), i % 48)); return a; });
  for (var r = 0; r < 3; r++) { var a = []; for (var i = 0; i < 336; i++) a.push(rnd() < 0.3); masks.push(a); }
  var edge = []; for (var i = 0; i < 336; i++) edge.push(i === 0 || i === 335 || i === 47 || i === 48); masks.push(edge);
  masks.forEach(function (a) {
    var h = qEncode(a);
    if (qDecode(h).join() !== a.join()) throw new Error('page: decode(encode(x)) != x');
    var txt = qText(a).replace(/–/g, '-').replace(/ · /g, '; ') || 'none';
    out.push(h + '\\t' + txt + '\\t' + a.map(function (x) { return x ? 1 : 0; }).join(''));
  });
  return out.join('\\n');`);
console.log(run());
EOF
[ "$(wc -l < "$t/masks.txt")" -ge 8 ] || { echo "::error::page encoder produced no masks"; exit 1; }

n=0
while IFS="$(printf '\t')" read -r mask want bits; do
	n=$((n + 1))
	# The script's reader on every half hour (at :00/:30 and :29/:59), as date +%w/%H/%M print them.
	got=$(PATH="$t/awkbin:$PATH" QUIET="$mask" "$bb" ash -c '
		. "$1"
		for d in 1 2 3 4 5 6 0; do
			h=0
			while [ $h -lt 24 ]; do
				hh=$(printf %02d $h)
				for m in 00 29 30 59; do
					if quiet_at $d $hh $m; then printf 1; else printf 0; fi
				done
				h=$((h + 1))
			done
		done' sh "$t/q.sh")
	# 4 probes per hour: :00 and :29 belong to the first half hour, :30 and :59 to the second.
	exp=$(printf '%s' "$bits" | sed 's/./&&/g')
	if [ "$got" = "$exp" ]; then ok "mask $n: script and page agree on all 336 half hours"
	else bad "mask $n: script reads the page's mask differently"; echo "      mask: $mask"; fi
	txt=$(PATH="$t/awkbin:$PATH" QUIET="$mask" "$bb" ash -c 'say() { printf "%s\n" "$*"; }; . "$1"; [ "$QUIET" = 000000000000000000000000000000000000000000000000000000000000000000000000000000000000 ] && QUIET=""; quiet_text' sh "$t/q.sh")
	short=$(printf '%s' "$txt" | cut -c1-60); [ "$short" = "$txt" ] || short="$short..."
	if [ "$txt" = "$want" ]; then ok "mask $n: summary '$short'"
	else bad "mask $n: script summary '$txt', page '$want'"; fi
done < "$t/masks.txt"

# ---- a router stand-in for the rest ----------------------------------------------------------
R=$t/root; F=$t/fix
mkdir -p "$R/jffs/addons/wifiinsight" "$R/jffs/scripts" "$R/www/user" "$R/tmp" "$R/usr/sbin" "$F" "$t/bin"
cp "$script" "$R/jffs/addons/wifiinsight/wifiinsight.sh"
"$bb" --list > "$t/bb.list"
grep -v '^#' "$here/merlin-applets.txt" | while IFS= read -r a; do
	[ -n "$a" ] || continue
	if grep -qxF -- "$a" "$t/bb.list"; then ln -s "$bb" "$t/bin/$a"
	elif p=$(command -v -- "$a"); then ln -s "$p" "$t/bin/$a"
	fi
done
rm -f "$t/bin/logger"
printf '#!/bin/sh\nshift 2; echo "$*" >> "%s/log"\n' "$F" > "$t/bin/logger"
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
chmod +x "$t/bin/logger" "$t/bin/nvram" "$t/bin/wl" "$t/bin/cru"
cat > "$R/usr/sbin/helper.sh" <<EOF
am_settings_get() { sed -n "s/^\$1 //p" "$F/settings"; }
EOF
CONF=$R/jffs/addons/wifiinsight/config
base_conf() { printf 'SAMPLE_INTERVAL=30\nSCAN_INTERVAL=%s\nRETAIN_DAYS=30\nDATA_DIR="%s"\nSQLITE="/nonexistent"\n' "${1:-30}" "$t/data" > "$CONF"; }
echo 'enable -n test [ printf echo' > "$t/no-builtins.sh"
run() { WI_ROOT="$R" TZ=UTC PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" "$@"; }
jobs() { sed -n 's/.*#wifiinsight_\(.*\)#$/\1/p' "$F/crontab" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//'; }
settings() { printf 'wifiinsight_sample 30\nwifiinsight_scan %s\nwifiinsight_retain 30\nwifiinsight_ownssids \nwifiinsight_mode %s\nwifiinsight_quiet %s\n' "$1" "$2" "$3" > "$F/settings"; }
expect() {   # name want got
	if [ "$3" = "$2" ]; then ok "$1"; else bad "$1"; echo "      want: $2"; echo "      got:  $3"; fi
}
ALL0=000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ALL1=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
EVE=000000000fff000000000fff000000000fff000000000fff000000000fff000000000fff000000000fff

# ---- 3: saving from the page --------------------------------------------------------------------
save() { : > "$F/log"; run service_event start wifiinsightconfig > "$t/out" 2>&1 || true; }
base_conf 30
settings 30 on "$EVE"; save
expect "save on + evenings: cron" "collect prune scan trickle" "$(jobs)"
expect "save on + evenings: config" "COLLECTION=on|QUIET=\"$EVE\"" "$(sed -n 's/^\(COLLECTION=[a-z]*\).*/\1/p; s/^\(QUIET=.*\)/\1/p' "$CONF" | tr '\n' '|' | sed 's/|$//')"
expect "save on + evenings: logged" "1" "$(grep -c 'settings updated: collection=on .*quiet=Mon-Sun 18:00-24:00' "$F/log" || true)"
settings 30 paused "$EVE"; save
expect "save scans paused: no scan job" "collect prune" "$(jobs)"
settings 30 off "$EVE"; save
expect "save off: no jobs" "" "$(jobs)"
settings 30 sleep "zz$EVE"; save
expect "invalid mode and mask keep the saved values" "COLLECTION=off|QUIET=\"$EVE\"" "$(sed -n 's/^\(COLLECTION=[a-z]*\).*/\1/p; s/^\(QUIET=.*\)/\1/p' "$CONF" | tr '\n' '|' | sed 's/|$//')"
settings 30 on "$(printf '%s' "$EVE" | sed 's/^0/A/')"; save
expect "upper-case or short masks from the page are refused" "QUIET=\"$EVE\"" "$(grep '^QUIET=' "$CONF")"
settings 0 on "$ALL0"; save
expect "save on, scans off, no quiet hours: no scan job" "collect prune" "$(jobs)"
expect "all-zero mask means no quiet hours" 'QUIET=""' "$(grep '^QUIET=' "$CONF")"
settings 120 on "$ALL0"; save
expect "2-hourly scans" "7 */2 * * *" "$(grep '#wifiinsight_scan#' "$F/crontab" | cut -d' ' -f1-5)"

# ---- 4: what the scheduled jobs do --------------------------------------------------------------
scanrun() { : > "$F/log"; rm -f "$R/www/user/wifiinsight/scanstate.htm"; run scan --delay > /dev/null 2>&1 || true; }
base_conf 30; printf 'COLLECTION=on\nQUIET="%s"\n' "$ALL1" >> "$CONF"; scanrun
expect "scheduled scan in quiet hours: skipped and logged" "scheduled scan skipped: quiet hours" "$(cat "$F/log")"
expect "scheduled scan in quiet hours: nothing written for the page" "no" "$( [ -f "$R/www/user/wifiinsight/scanstate.htm" ] && echo yes || echo no)"
base_conf 30; printf 'COLLECTION=on\nQUIET=""\n' >> "$CONF"; scanrun
expect "scheduled scan outside quiet hours: runs (stops at not ready here)" "yes" "$( [ -f "$R/www/user/wifiinsight/scanstate.htm" ] && echo yes || echo no)"
base_conf 30; printf 'COLLECTION=paused\nQUIET=""\n' >> "$CONF"; scanrun
expect "scheduled scan while paused: does nothing" "no" "$( [ -f "$R/www/user/wifiinsight/scanstate.htm" ] && echo yes || echo no)"
base_conf 30; printf 'COLLECTION=on\nQUIET="%s"\n' "$ALL1" >> "$CONF"; : > "$F/log"; run scan > /dev/null 2>&1 || true
expect "Scan now in quiet hours: runs" "yes" "$( [ -f "$R/www/user/wifiinsight/scanstate.htm" ] && echo yes || echo no)"
# quiet_now uses the router's local time: a mask with only the current half hour set, in a time zone far from UTC.
base_conf 30
mask=$(TZ=Pacific/Auckland "$node" -e '
	const p = new Intl.DateTimeFormat("en-GB", { timeZone: "Pacific/Auckland", weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date());
	const g = k => p.find(x => x.type === k).value, d = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"].indexOf(g("weekday"));
	const s = d * 48 + (+g("hour")) * 2 + (+g("minute") >= 30 ? 1 : 0), a = [];
	for (let i = 0; i < 84; i++) { let v = 0; for (let b = 0; b < 4; b++) if (i * 4 + b === s) v |= 8 >> b; a.push(v.toString(16)); }
	console.log(a.join(""))')
printf 'COLLECTION=on\nQUIET="%s"\n' "$mask" >> "$CONF"
st=$(WI_ROOT="$R" TZ=NZST-12NZDT,M9.5.0,M4.1.0/3 PATH="$t/bin" BASH_ENV="$t/no-builtins.sh" "$bash_bin" "$R/jffs/addons/wifiinsight/wifiinsight.sh" status 2>&1 | grep '^Quiet hours:')
case "$st" in *"(quiet now)") ok "quiet now follows the router's local time ($st)" ;;
	*) sleep 2; bad "quiet now in the router's time zone: $st" ;; esac
base_conf 30; printf 'COLLECTION=off\n' >> "$CONF"; : > "$F/log"
mkdir -p "$t/data"; run collect --once > "$t/out" 2>&1 || true
expect "collect when off: does nothing" "" "$(cat "$t/out" "$F/log")"

# ---- 5: hand-edited config ------------------------------------------------------------------------
status_q() { run status 2>/dev/null | sed -n 's/^Quiet hours: //p'; }
status_c() { run status 2>/dev/null | sed -n 's/^Collection:  //p'; }
base_conf 30; printf 'QUIET="%s"\n' "$(printf '%s' "$EVE" | tr abcdef ABCDEF)" >> "$CONF"
expect "upper-case mask in the config is read" "Mon-Sun 18:00-24:00" "$(status_q | sed 's/ (quiet now)//')"
base_conf 30; printf 'QUIET="fff"\n' >> "$CONF"
expect "short mask in the config is ignored" "none (the QUIET line in the config is invalid, so it is ignored)" "$(status_q)"
base_conf 30; printf 'QUIET="%s"\n' "$(printf '%s' "$EVE" | sed 's/^0/g/')" >> "$CONF"
expect "non-hex mask in the config is ignored" "none (the QUIET line in the config is invalid, so it is ignored)" "$(status_q)"
base_conf 30; printf 'COLLECTION=sometimes\n' >> "$CONF"
expect "unknown COLLECTION means on" "on: samples every 30 s, neighbour scans every 30 min" "$(status_c)"
base_conf 30
expect "a config from before 1.1.0 means on, no quiet hours" "on: samples every 30 s, neighbour scans every 30 min|none" "$(status_c)|$(status_q)"

[ $fail -eq 0 ] && echo "Quiet hours: all checks passed." || { echo "::error::Quiet hours: some checks failed."; exit 1; }
