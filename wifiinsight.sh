#!/bin/sh
###############################################################################
#  WiFi Insight for Asuswrt-Merlin
#  Channel interference history, channel-change events and a spectrum
#  heatmap for Broadcom-based Merlin routers (built on an RT-AX86U).
#
#  Pages: Insight, Site Survey, Channel Statistics, Troubleshooting, Settings
#
#  Usage: wifiinsight.sh                    (a menu, when run in a terminal: amtm opens this)
#         wifiinsight.sh install | update [force | dev [branch]] | uninstall [--keep-data] | status | scan |
#                        collection [on|paused|off] | debug | amtmupdate [check] |
#                        startup | collect | export | prune
#
#  Install:  curl -fsL --retry 3 https://github.com/IfSugar/wifiinsight/releases/latest/download/wifiinsight.sh \
#              -o /tmp/wifiinsight.sh && sh /tmp/wifiinsight.sh install
###############################################################################

VERSION="1.3.1"
NAME="wifiinsight"
TITLE="WiFi Insight"

# WI_ROOT lets the script be tested off-router; it is empty on the router.
ROOT="${WI_ROOT:-}"
ADDON_DIR="$ROOT/jffs/addons/$NAME"
SCRIPT="$ADDON_DIR/$NAME.sh"
PAGE_SRC="$ADDON_DIR/$NAME.asp"
CONF="$ADDON_DIR/config"
BUILD_FILE="$ADDON_DIR/build"   # "dev <branch> <commit> <installed>" for a development version; none for a release
SCRIPTS_DIR="$ROOT/jffs/scripts"
HELPER="$ROOT/usr/sbin/helper.sh"
WWW_USER="$ROOT/www/user"
MENUTREE="$ROOT/www/require/modules/menuTree.js"
TMP_MENUTREE="$ROOT/tmp/menuTree.js"
WEBUI_LOCK="$ROOT/tmp/addonwebui.lock"
SCAN_FLAG="$ROOT/tmp/$NAME.scanning"
TMPD="$ROOT/tmp/$NAME"
CHART_URL="https://cdn.jsdelivr.net/npm/chart.js@4.6.1/dist/chart.umd.min.js"
CHART_SHA256="87364cc2b2a76a6684929e7d6b80b18a897794db38400caff1fcf1791c6925d2"   # npm chart.js@4.6.1
REPO="IfSugar/wifiinsight"
RAW_BASE="https://raw.githubusercontent.com/$REPO"
RAW_URL="${WI_RAW_URL:-$RAW_BASE/main}"   # WI_RAW_URL: test hook only

[ -z "$ROOT" ] && PATH="/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin:$PATH"
export PATH
if [ -z "$TZ" ] && [ -f "$ROOT/etc/TZ" ]; then TZ="$(cat "$ROOT/etc/TZ")"; export TZ; fi

# ---- defaults (overridden by $CONF) ----------------------------------------
SAMPLE_INTERVAL=30      # seconds between interference samples: 30 or 60
SCAN_INTERVAL=30        # minutes between neighbour scans (0 = never)
RETAIN_DAYS=30          # history kept for samples and scans
EXTRA_OWN_SSIDS=""      # extra SSIDs to treat as yours, separated by |
COLLECTION=on           # on, paused (no scheduled scans) or off (no samples or scans)
QUIET=""                # quiet hours, no scheduled scans: see quiet_at() below
AMTM_UPDATE=on          # on: amtm may update WiFi Insight (amtmupdate); off: only 'update' does
DATA_DIR="/opt/var/lib/$NAME"
SQLITE="/opt/bin/sqlite3"
[ -f "$CONF" ] && . "$CONF"
DB="$DATA_DIR/$NAME.db"
case "$COLLECTION" in on|paused|off) ;; *) COLLECTION=on ;; esac
case "$AMTM_UPDATE" in on|off) ;; *) AMTM_UPDATE=on ;; esac
case "$QUIET" in *[A-F]*) QUIET=$(printf '%s' "$QUIET" | tr ABCDEF abcdef) ;; esac
QUIET_BAD=""
case "${#QUIET}:$QUIET" in
	0:) ;;
	84:*[!0-9a-f]*) QUIET_BAD=1; QUIET="" ;;
	84:*) case "$QUIET" in *[!0]*) ;; *) QUIET="" ;; esac ;;   # all zeros: none
	*) QUIET_BAD=1; QUIET="" ;;
esac

# ---- helpers ---------------------------------------------------------------
log() { logger -t "$NAME" "$*" 2>/dev/null; }
say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
now() { date +%s; }
sq() { printf '%s' "$1" | sed "s/'/''/g"; }                  # SQL-quote body
js() { printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }   # JSON string body
num() { case "$1" in ''|-|?*-*|*[!0-9-]*) echo NULL ;; *) echo "$1" ;; esac; }    # SQL number
jnum() { case "$1" in ''|-|?*-*|*[!0-9-]*) echo null ;; *) echo "$1" ;; esac; }   # JSON number

# Is a program on PATH? (Router BusyBox builds can lack the `command` builtin, so walk PATH.)
have() {
	case "$1" in */*) [ -f "$1" ] && [ -x "$1" ]; return ;; esac
	_ifs=$IFS; IFS=:
	for _d in $PATH; do
		if [ -f "${_d:-.}/$1" ] && [ -x "${_d:-.}/$1" ]; then IFS=$_ifs; return 0; fi
	done
	IFS=$_ifs; return 1
}

sha256_of() {
	if have sha256sum; then sha256sum "$1" | cut -d' ' -f1
	elif have openssl; then openssl dgst -sha256 "$1" | awk '{print $NF}'
	fi
}
chart_ok() {   # the downloaded Chart.js is byte-identical to the published npm release
	h=$(sha256_of "$1")
	[ -n "$h" ] || { say "No sha256 tool found; keeping Chart.js without checking it."; return 0; }
	[ "$h" = "$CHART_SHA256" ]
}

# sqlite's errors still go to stderr. "malformed" or "not a database" also marks the database as damaged
# (a power cut while the USB drive was writing, say), which status and the page report until 'repair'.
sql() {
	{ _sqe=$("$SQLITE" -batch -noheader -cmd ".timeout 8000" "$DB" "$@" 2>&1 1>&3 3>&-); _sqr=$?; } 3>&1
	if [ -n "$_sqe" ]; then
		printf '%s\n' "$_sqe" >&2
		case "$_sqe" in *malformed*|*"not a database"*)
			[ -f "$DATA_DIR/damaged" ] || { now > "$DATA_DIR/damaged"; log "the database is damaged ($(printf '%s' "$_sqe" | head -1 | cut -c1-80)): run '$SCRIPT repair'"; } 2>/dev/null ;;
		esac
	fi
	return $_sqr
}

# Big query results (a day of samples is ~350 KB of JSON) must never sit in a shell variable or
# be passed as an argument. Merlin's BusyBox runs [, printf and echo as separate programs, and
# Linux refuses any single argument over 128 KB, so they would fail. Stream them instead.
json_out() {   # default query: print the query's JSON, or the default if it printed nothing (DB busy)
	mkdir -p "$TMPD"; jf="$TMPD/json.$$"
	sql "$2" > "$jf" 2>/dev/null
	if [ -s "$jf" ]; then tr -d '\n' < "$jf"; else printf '%s' "$1"; fi
	rm -f "$jf"
}

# Background work runs at the lowest CPU priority, so routing, Wi-Fi and the web UI always come first.
lowprio() { renice -n 19 -p $$ >/dev/null 2>&1 || true; }

state_get() { sql "SELECT v FROM state WHERE k='$(sq "$1")';" 2>/dev/null; }   # fails if the DB is busy
state_sql() { printf "INSERT OR REPLACE INTO state(k,v) VALUES('%s','%s');\n" "$(sq "$1")" "$(sq "$2")"; }

ready() {
	# Collect only when NTP has synced and Entware/USB storage is mounted.
	[ "$(nvram get ntp_ready)" = "1" ] || return 1
	[ -x "$SQLITE" ] || return 1
	[ -d "$DATA_DIR" ] || return 1
	return 0
}

web_dir() {
	d="$(readlink -f "$WWW_USER" 2>/dev/null)"
	[ -n "$d" ] || d="$WWW_USER"
	echo "$d/$NAME"
}

radios() { for i in 0 1 2; do [ -n "$(nvram get wl${i}_ifname)" ] && echo "$i"; done; }

# Chanspec bits, as in Broadcom's bcmwifi_channels.h. Band (0xc000): 0x0000 2.4 GHz, 0x4000 6 GHz,
# 0x8000 4.9 GHz (counted as 5), 0xc000 5 GHz. Width (0x3800): 0x1000 20, 0x1800 40, 0x2000 80,
# 0x2800 160, 0x3000 80+80, and 0x0000 is 320 MHz on 6 GHz. Up to 1.1.0, 6 GHz was misread as 5 GHz.
band_of_hex() {
	case $(( $1 & 0xc000 )) in
		0) echo 2g ;; 16384) echo 6g ;; *) echo 5g ;;
	esac
}

width_of_hex() {
	case $(( ($1 & 0x3800) >> 11 )) in
		2) echo 20 ;; 3) echo 40 ;; 4) echo 80 ;; 5|6) echo 160 ;; 7) echo 320 ;;
		0) if [ $(( $1 & 0xc000 )) -eq 16384 ]; then echo 320; else echo 20; fi ;;
		*) echo 20 ;;
	esac
}

ctl_of_cs() {
	c="${1#6g}"; c="${c%%[!0-9]*}"; echo "${c:-0}"
}

# ---- database ---------------------------------------------------------------
init_db() {
	sql <<'EOF'
CREATE TABLE IF NOT EXISTS samples(
  ts INTEGER NOT NULL, band TEXT NOT NULL, hex TEXT, cs TEXT,
  ctl INTEGER, width INTEGER, center INTEGER,
  tx INTEGER, inbss INTEGER, obss INTEGER, nocat INTEGER, nopkt INTEGER,
  doze INTEGER, txop INTEGER, goodtx INTEGER, badtx INTEGER, glitch INTEGER,
  badplcp INTEGER, knoise INTEGER, idle INTEGER, noise INTEGER, stamp INTEGER,
  PRIMARY KEY(band, ts));
CREATE INDEX IF NOT EXISTS sa_ts ON samples(ts);
CREATE TABLE IF NOT EXISTS events(
  ts INTEGER NOT NULL, band TEXT, tag TEXT, old TEXT, new TEXT, detail TEXT,
  UNIQUE(ts, band, tag));
CREATE INDEX IF NOT EXISTS ev_ts ON events(ts);
CREATE TABLE IF NOT EXISTS scans(
  ts INTEGER NOT NULL, band TEXT, ch INTEGER, score REAL, aps INTEGER,
  best INTEGER, own REAL);
CREATE INDEX IF NOT EXISTS sc_bt ON scans(band, ts);
CREATE TABLE IF NOT EXISTS aps(
  ts INTEGER NOT NULL, band TEXT, bssid TEXT, ssid TEXT, rssi INTEGER,
  ctl INTEGER, center INTEGER, width INTEGER, util INTEGER, own INTEGER,
  phy TEXT, sec TEXT, snr INTEGER);
CREATE INDEX IF NOT EXISTS ap_bt ON aps(band, ts);
CREATE TABLE IF NOT EXISTS chanim(
  ts INTEGER NOT NULL, band TEXT NOT NULL, ch INTEGER NOT NULL, obss INTEGER, nocat INTEGER,
  nopkt INTEGER, glitch INTEGER, badplcp INTEGER, noise INTEGER, PRIMARY KEY(band, ts, ch));
CREATE TABLE IF NOT EXISTS state(k TEXT PRIMARY KEY, v TEXT);
EOF
}

# ---- sampling ---------------------------------------------------------------
# Print: chanspec tx inbss obss nocat nopkt doze txop goodtx badtx glitch badplcp
#        knoise idle timestamp   (columns located by header name)
# Two layouts exist. Wi-Fi 6 drivers ("version: 3"): a "chanspec" header and hex chanspecs
# (0x1006). Wi-Fi 7 drivers ("version: 4"): a "chspec" header, readable chanspecs (6, 36/160),
# "timestamps", and an extra "busy" column. Prefers the row for the radio's current chanspec
# ($1 readable, $2 hex) when there are several; otherwise the last one.
parse_chanim() {
	awk -v cs="$1" -v hex="$2" '
	$1 == "chanspec" || $1 == "chspec" {
		for (i = 1; i <= NF; i++) col[$i] = i
		col["chanspec"] = 1
		if (!("timestamp" in col) && ("timestamps" in col)) col["timestamp"] = col["timestamps"]
		ncol = NF; hdr = 1; next
	}
	hdr && NF >= ncol - 1 && $1 !~ /^(version|state)/ {
		line = $0
		if ((cs != "" && $1 == cs) || (hex != "" && tolower($1) == tolower(hex))) cur = $0
	}
	END {
		if (cur != "") line = cur
		if (line == "") exit 1
		sub(/^[ \t]+/, "", line)
		split(line, v, /[ \t]+/)
		out = v[col["chanspec"]]
		n = split("tx inbss obss nocat nopkt doze txop goodtx badtx glitch badplcp knoise idle timestamp", names, " ")
		for (j = 1; j <= n; j++) {
			k = names[j]; val = "NULL"
			if (k in col) { val = v[col[k]]; if (val !~ /^-?[0-9]+$/) val = "NULL" }
			out = out " " val
		}
		print out
	}'
}

sample_all() {
	ts=$(now)
	out=""
	for r in $(radios); do
		ifc=$(nvram get wl${r}_ifname)
		[ "$(wl -i "$ifc" isup 2>/dev/null)" = "1" ] || continue
		csl=$(wl -i "$ifc" chanspec 2>/dev/null) || continue
		cs=${csl%% *}
		hex=$(printf '%s' "$csl" | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p')
		[ -n "$hex" ] || continue
		p=$(wl -i "$ifc" chanim_stats 2>/dev/null | parse_chanim "$cs" "$hex") || continue
		set -- $p
		[ $# -ge 15 ] || continue
		shift   # drop chanim's own chanspec; use the live one
		stamp=${14}
		laststamp=$(state_get "stamp_wl$r")
		[ -n "$stamp" ] && [ "$stamp" != "NULL" ] && [ "$stamp" = "$laststamp" ] && continue  # stale
		band=$(band_of_hex "$hex"); width=$(width_of_hex "$hex"); center=$(( hex & 0xff ))
		ctl=$(ctl_of_cs "$cs"); noise=$(num "$(wl -i "$ifc" noise 2>/dev/null)")
		out="${out}INSERT OR REPLACE INTO samples VALUES($ts,'$band','$hex','$(sq "$cs")',$ctl,$width,$center,$1,$2,$3,$4,$5,$6,$7,$8,$9,${10},${11},${12},${13},$noise,${14});
$(state_sql "stamp_wl$r" "$stamp")
"
		out="${out}$(detect_change "$r" "$band" "$hex" "$cs" "$width" "$ts")
"
	done
	[ -n "$out" ] && printf 'BEGIN;\n%sCOMMIT;\n' "$out" | sql
}

# ---- events -----------------------------------------------------------------
ev_sql() {   # ts band tag old new detail
	printf "INSERT OR IGNORE INTO events VALUES(%s,'%s','%s','%s','%s','%s');\n" \
		"$1" "$2" "$3" "$(sq "$4")" "$(sq "$5")" "$(sq "$6")"
}

tomin() {   # HHMM -> minutes since midnight
	h=${1%??}; m=${1#??}; echo $(( (1$h - 100) * 60 + (1$m - 100) ))
}

pretty_cs() {   # cs width -> "100 / 40 MHz"
	echo "$(ctl_of_cs "$1") / $2 MHz"
}

detect_change() {   # radio band hex cs width ts  -> prints SQL
	r=$1; band=$2; hex=$3; cs=$4; width=$5; ts=$6
	last=$(state_get "hex_wl$r") || return 0   # DB busy: never mistake that for a first run
	lastw=$(state_get "width_wl$r"); lastcs=$(state_get "cs_wl$r")
	nvcs=$(nvram get wl${r}_chanspec); nvbw=$(nvram get wl${r}_bw)
	lnvcs=$(state_get "nvcs_wl$r"); lnvbw=$(state_get "nvbw_wl$r")
	if [ -z "$last" ]; then
		ev_sql "$ts" "$band" initial "" "$(pretty_cs "$cs" "$width")" "Monitoring started on $(pretty_cs "$cs" "$width")"
	elif [ "$last" != "$hex" ]; then
		old="$(pretty_cs "$lastcs" "$lastw")"; new="$(pretty_cs "$cs" "$width")"
		recent_radar=$(sql "SELECT count(*) FROM events WHERE band='$band' AND tag='radar' AND ts>=$((ts-600));")
		if [ "$nvcs" != "$lnvcs" ] || [ "$nvbw" != "$lnvbw" ]; then tag=manual; why="Channel settings were changed"
		elif [ "${recent_radar:-0}" -gt 0 ]; then tag=radar; why="Moved after radar detection"
		elif [ "$(ctl_of_cs "$cs")" = "$(ctl_of_cs "$lastcs")" ]; then tag=bandwidth; why="Bandwidth changed on the same channel"
		elif pidof acsd2 acsd >/dev/null 2>&1; then tag=auto; why="Automatic channel selection"
		else tag=changed; why="Channel changed"
		fi
		ev_sql "$ts" "$band" "$tag" "$old" "$new" "$why"
	fi
	state_sql "hex_wl$r" "$hex"; state_sql "width_wl$r" "$width"; state_sql "cs_wl$r" "$cs"
	state_sql "nvcs_wl$r" "$nvcs"; state_sql "nvbw_wl$r" "$nvbw"
}

detect_restart() {
	ts=$(now); up=$(awk '{ print int($1) }' "${WI_UPTIME_FILE:-/proc/uptime}" 2>/dev/null)
	case "$up" in ''|*[!0-9]*) return 0 ;; esac
	lastup=$(state_get uptime) || return 0
	lastboot=$(state_get boot) || return 0
	boot=$((ts - up)); s=""
	# A restart shows as the uptime going backwards, or the boot time moving forward
	# (catches a reboot that happened soon after the previous one).
	if [ -n "$lastup" ] && { [ "$up" -lt "$lastup" ] || { [ -n "$lastboot" ] && [ $((boot - lastboot)) -gt 300 ]; }; }; then
		tag=restart; why="Router restarted"
		if [ "$(nvram get reboot_schedule_enable)" = "1" ]; then
			rs=$(nvram get reboot_schedule)        # e.g. 11111110500: Sun..Sat flags + HHMM
			dow=$(date -d "@$boot" +%w 2>/dev/null)
			bh=$(date -d "@$boot" +%H%M 2>/dev/null)
			flag=$(printf '%s' "$rs" | cut -c$((dow + 1)) 2>/dev/null)
			hm=$(printf '%s' "$rs" | cut -c8-11)
			if [ "$flag" = "1" ] && [ -n "$hm" ] && [ -n "$bh" ]; then
				d=$(( $(tomin "$bh") - $(tomin "$hm") ))
				[ "$d" -ge 0 ] && [ "$d" -le 15 ] && { tag=scheduled; why="Scheduled reboot"; }
			fi
		fi
		s="$(ev_sql "$boot" all "$tag" "" "" "$why")"
	fi
	printf 'BEGIN;\n%s\n%s\n%s\nCOMMIT;\n' "$s" "$(state_sql uptime "$up")" "$(state_sql boot "$boot")" | sql
}

detect_radar() {
	files=""
	for f in "$ROOT/jffs/syslog.log-1" "$ROOT/jffs/syslog.log" "$ROOT/tmp/syslog.log-1" "$ROOT/tmp/syslog.log" "/opt/var/log/messages"; do
		[ -f "$f" ] && files="$files $f"
	done
	[ -n "$files" ] || return
	# The radar lines go through a file, not a variable: a long-kept log can hold more than
	# a command argument may (see json_out).
	mkdir -p "$TMPD"; lf="$TMPD/radar.$$"
	grep -ih "radar detected" $files 2>/dev/null | sort -u > "$lf"
	[ -s "$lf" ] || { rm -f "$lf"; return; }
	sig=$(awk 'NR > 1 { printf "\n" } { printf "%s", $0 }' "$lf" | md5sum | cut -c1-32)
	[ "$sig" = "$(state_get radar_sig)" ] && { rm -f "$lf"; return; }
	year=$(date +%Y); nowts=$(now)
	maps=""; for r in $(radios); do maps="$maps $(nvram get wl${r}_ifname)=$r wl$r=$r"; done
	{
	echo 'BEGIN;'
	while IFS= read -r line; do
		mon=$(printf '%s' "$line" | cut -c1-3); day=$(printf '%s' "$line" | cut -c5-6 | tr -d ' ')
		hms=$(printf '%s' "$line" | cut -c8-15)
		m=$(echo "JanFebMarAprMayJunJulAugSepOctNovDec" | awk -v m="$mon" '{ i = index($0, m); print (i ? (i + 2) / 3 : 0) }')
		[ "$m" -gt 0 ] 2>/dev/null || continue
		t=$(date -d "$year-$m-$day $hms" +%s 2>/dev/null) || continue
		[ "$t" -gt $((nowts + 86400)) ] && t=$(date -d "$((year - 1))-$m-$day $hms" +%s 2>/dev/null)
		band=5g; det="Radar detected"
		for mp in $maps; do
			ifn=${mp%=*}; r=${mp#*=}
			case "$line" in *"$ifn:"*|*"$ifn "*)
				ifc=$(nvram get wl${r}_ifname)   # the log may name the radio as ethN or wlN
				det="Radar detected on $ifc"
				h=$(wl -i "$ifc" chanspec 2>/dev/null | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p')
				[ -n "$h" ] && band=$(band_of_hex "$h") ;;
			esac
		done
		ev_sql "$t" "$band" radar "" "" "$det"
	done < "$lf"
	state_sql radar_sig "$sig"
	echo 'COMMIT;'
	} | sql
	rm -f "$lf"
}

# ---- scanning ---------------------------------------------------------------
own_ssids_file() {
	f="$TMPD/own_ssids"
	{
		for r in $(radios); do
			nvram get wl${r}_ssid
			# guest networks: wlX.1-3, and higher on 3006.102 (Guest Network Pro)
			for g in 1 2 3 4 5 6 7; do [ "$(nvram get wl${r}.${g}_bss_enabled)" = "1" ] && nvram get wl${r}.${g}_ssid; done
		done
		[ -n "$EXTRA_OWN_SSIDS" ] && printf '%s\n' "$EXTRA_OWN_SSIDS" | tr '|' '\n'
	} | grep -v '^$' | sort -u > "$f"
	echo "$f"
}

default_channels() {
	case "$1" in
		2g) echo "1 2 3 4 5 6 7 8 9 10 11 12 13" ;;
		6g) echo "1 5 9 13 17 21 25 29 33 37 41 45 49 53 57 61 65 69 73 77 81 85 89 93" ;;
		*)  echo "36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140" ;;
	esac
}

radio_channels() {   # ifc band
	c=$(wl -i "$1" channels 2>/dev/null | tr -s ' \t\n' ' ' | sed 's/^ //; s/ $//')
	case "$c" in ''|*[!0-9\ ]*) c=$(default_channels "$2") ;; esac
	echo "$c"
}

# stdin: `wl scanresults`; prints SQL for aps + per-channel scores
parse_scan() {   # ts band "channels" ownfile
	LC_ALL=C awk -v ts="$1" -v band="$2" -v chans="$3" -v ownfile="$4" '
	# wl prints non-printable SSID bytes (UTF-8 included) as \xNN and doubles backslashes;
	# turn them back into the raw bytes nvram holds so own SSIDs match and names display right.
	function unesc(s,   o, i, c, n, H) {
		H = "0123456789ABCDEF"; o = ""
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c == "\\" && substr(s, i + 1, 1) == "\\") { o = o "\\"; i++ }
			else if (c == "\\" && substr(s, i + 1, 1) == "x" && toupper(substr(s, i + 2, 2)) ~ /^[0-9A-F][0-9A-F]$/) {
				n = (index(H, toupper(substr(s, i + 2, 1))) - 1) * 16 + index(H, toupper(substr(s, i + 3, 1))) - 1
				if (n > 0) o = o sprintf("%c", n)
				i += 3
			} else o = o c
		}
		return o
	}
	function freq(c) {
		if (band == "2g") return (c == 14) ? 2484 : 2407 + 5 * c
		if (band == "6g") return 5950 + 5 * c
		return 5000 + 5 * c
	}
	function esc(s) { gsub(/\047/, "\047\047", s); return s }
	function flush(   base, nb) {
		if (!have) return
		if (width == "" && chf != "") {
			split(chf, q, "/"); if (ctl == "") ctl = q[1] + 0; width = (q[2] != "") ? q[2] + 0 : 20
		}
		if (width == "") width = 20
		if (ctl == "" && center != "") ctl = center
		if (ctl == "") { have = 0; return }
		if (center == "") {
			center = ctl
			if (band != "2g" && width > 20) {
				nb = width / 20; base = (ctl >= 149) ? 149 : (ctl >= 100) ? 100 : 36
				if (band == "6g") base = 1
				center = base + int((ctl - base) / (4 * nb)) * 4 * nb + (nb - 1) * 2
			}
		}
		if (rssi == "") rssi = -100
		if (bssid != "" && (bssid in seenb)) { have = 0; return }   # heard again by a follow-up scan
		seenb[bssid] = 1
		n++
		S[n] = ssid; B[n] = bssid; R[n] = rssi + 0; C[n] = ctl + 0; M[n] = center + 0
		W[n] = width + 0; U[n] = util; O[n] = (ssid in own) ? 1 : 0
		P[n] = (eht ? "be" : he ? "ax" : vht ? "ac" : ht ? "n" : (band == "2g" ? "g" : "a"))
		if (sae && psk) sec = "WPA2/WPA3"; else if (sae) sec = "WPA3"
		else if (rsn && ent) sec = rsn_wpa ? "WPA/WPA2-Ent" : "WPA2-Ent"
		else if (rsn) sec = wpa ? "WPA/WPA2" : "WPA2"
		else if (wpa) sec = "WPA"; else if (wep) sec = "WEP"; else sec = "Open"
		X[n] = sec; N[n] = (snr == "") ? -1 : snr + 0
		have = 0
	}
	BEGIN {
		n = 0
		if (ownfile != "") while ((getline l < ownfile) > 0) if (l != "") own[l] = 1
	}
	/^SSID: / {
		flush(); have = 1
		s = $0; a = index(s, "\""); b = 0
		for (i = length(s); i > a; i--) if (substr(s, i, 1) == "\"") { b = i; break }
		ssid = (a && b) ? unesc(substr(s, a + 1, b - a - 1)) : ""
		rssi = ""; bssid = ""; ctl = ""; center = ""; width = ""; util = -1; chf = ""; snr = ""
		eht = he = vht = ht = 0; sae = psk = rsn = wpa = wep = ent = rsn_wpa = 0
		next
	}
	!have { next }
	/^Mode: / {
		if (match($0, /RSSI: -?[0-9]+/)) { t = substr($0, RSTART + 6, RLENGTH - 6); rssi = t + 0 }
		if (match($0, /Channel: (6g)?[0-9]+(\/[0-9]+)?/)) { chf = substr($0, RSTART + 9, RLENGTH - 9); sub(/^6g/, "", chf) }
		if (match($0, /SNR: -?[0-9]+/)) snr = substr($0, RSTART + 5, RLENGTH - 5) + 0
		next
	}
	/^BSSID: / { bssid = $2; if ($0 ~ /Capability:.*WEP/) wep = 1; next }
	/^EHT Capable/ { eht = 1; next }
	/^HE Capable/ { he = 1; next }
	/^VHT Capable/ { vht = 1; next }
	/^HT Capable/ { ht = 1; next }
	/^RSN/ { rsn = 1; insec = "rsn"; next }
	/^WPA:/ { wpa = 1; insec = "wpa"; next }
	/AKM Suites/ {
		if ($0 ~ /SAE/) sae = 1
		if ($0 ~ /PSK/) psk = 1
		if ($0 ~ /802\.1[xX]|UNSPECIFIED|SUITE-B|FT-802/) ent = 1
		if (insec == "rsn" && wpa) rsn_wpa = 1
		next
	}
	/Chanspec: / {
		if (match($0, /channel [0-9]+ [0-9]+MHz/)) {
			t = substr($0, RSTART, RLENGTH); split(t, p, " ")
			center = p[2] + 0; w = p[3]; sub(/MHz/, "", w); width = w + 0
		}
		next
	}
	/Primary channel: / { t = $0; sub(/.*Primary channel: */, "", t); ctl = t + 0; next }
	/QBSS Channel Utilization:/ {
		if (match($0, /\([0-9]+ *%\)/)) { t = substr($0, RSTART + 1, RLENGTH - 2); gsub(/[ %]/, "", t); util = t + 0 }
		next
	}
	END {
		flush()
		# A hidden network from one of your own devices (an AiMesh node backhaul, Wi-Fi 7 links) is yours
		# too: its BSSID matches the BSSID of one of your named networks in all but the first byte and the
		# last 4 bits, which only the same device shares (variants of one base address).
		for (i = 1; i <= n; i++) if (O[i] && length(B[i]) == 17) dev[tolower(substr(B[i], 4, 13))] = 1
		for (i = 1; i <= n; i++)
			if (!O[i] && S[i] !~ /[^\001-\040]/ && length(B[i]) == 17 && (tolower(substr(B[i], 4, 13)) in dev)) O[i] = 1
		print "BEGIN;"
		for (i = 1; i <= n; i++)
			printf "INSERT INTO aps VALUES(%d,\047%s\047,\047%s\047,\047%s\047,%d,%d,%d,%d,%d,%d,\047%s\047,\047%s\047,%d);\n", ts, band, esc(B[i]), esc(S[i]), R[i], C[i], M[i], W[i], U[i], O[i], P[i], X[i], N[i]
		k = split(chans, CH, " ")
		for (j = 1; j <= k; j++) {
			c = CH[j] + 0; lo = freq(c) - 10; hi = freq(c) + 10
			sc = 0; ow = 0; cnt = 0; best = -127
			for (i = 1; i <= n; i++) {
				fc = freq(M[i]); alo = fc - W[i] / 2; ahi = fc + W[i] / 2
				ov = ((hi < ahi ? hi : ahi) - (lo > alo ? lo : alo)) / 20
				if (ov <= 0) continue
				if (ov > 1) ov = 1
				sig = (R[i] + 92) / 40; if (sig < 0) sig = 0; if (sig > 1) sig = 1
				load = (U[i] >= 0) ? U[i] : 25
				contrib = ov * sig * (15 + 0.85 * load)
				if (O[i]) ow += contrib
				else { sc += contrib; cnt++; if (R[i] > best) best = R[i] }
			}
			if (sc > 100) sc = 100
			if (ow > 100) ow = 100
			printf "INSERT INTO scans VALUES(%d,\047%s\047,%d,%.1f,%d,%d,%.1f);\n", ts, band, c, sc, cnt, best, ow
		}
		print "COMMIT;"
	}'
}

# stdin: `wl chanim_stats all`. After a scan the driver keeps what it measured on each channel it
# visited: the share of airtime used by other networks (obss), non-Wi-Fi energy (nocat) and energy
# it couldn't decode (nopkt), plus glitches, bad frame headers and the noise floor. txdur and inbss
# are left out: off-channel they're the scan's own probes and the replies to them.
# Layouts: 3004.388 (version 3) prints a block per channel under "Stats during last scan":
#    chanspec: 0xd024 crsglitch cnt: 0 bad plcp: 16 noise: -93
#   	 cca_txdur: 2 cca_inbss: 3 cca_obss:1 cca_nocat: 3 cca_nopkt: 1
# and a table with a chanspec/chspec header and a row per channel is read too (newer drivers print
# chanim_stats as a table). Prints SQL only for two or more channels: one row is just the radio's
# own channel, not a scan. Channels on another band are skipped.
parse_chanim_all() {   # ts band [raw]   raw: "channel<TAB>its figures as printed", to compare readings
	awk -v ts="$1" -v band="$2" -v raw="$3" '
	function hexval(s,   i, c, v) {
		s = tolower(s); sub(/^0x/, "", s); v = 0
		if (s == "") return -1
		for (i = 1; i <= length(s); i++) { c = index("0123456789abcdef", substr(s, i, 1)); if (!c) return -1; v = v * 16 + c - 1 }
		return v
	}
	function chan(cs,   v, b, t) {   # chanspec, hex or readable (36/80, 6g1/80, 11u) -> channel, -1 if another band
		if (cs ~ /^0[xX]/) {
			v = hexval(cs); if (v < 0) return -1
			b = int(v / 16384) % 4; t = (b == 0) ? "2g" : (b == 1) ? "6g" : "5g"
			return (t == band) ? v % 256 : -1
		}
		t = band
		if (cs ~ /^6g/) { t = "6g"; sub(/^6g/, "", cs) }
		if (!match(cs, /^[0-9]+/)) return -1
		return (t == band) ? substr(cs, 1, RLENGTH) + 0 : -1
	}
	function num(x) { return (x ~ /^-?[0-9]+$/) ? x + 0 : "NULL" }
	function pct(x) { x = num(x); return (x == "NULL") ? x : (x < 0 ? 0 : (x > 100 ? 100 : x)) }
	function val(key,   i, t) {   # the number after key on this line
		i = index($0, key); if (!i) return ""
		t = substr($0, i + length(key)); sub(/^[ \t]*/, "", t)
		return match(t, /^-?[0-9a-fA-Fx]+/) ? substr(t, 1, RLENGTH) : ""
	}
	function keep(c, o, n, p, g, b, z) {
		if (c < 0 || (c in seen) || o == "") return
		seen[c] = 1; k++
		if (raw != "") { out[k] = c "\t" blk; return }
		out[k] = sprintf("INSERT OR REPLACE INTO chanim VALUES(%d,\047%s\047,%d,%s,%s,%s,%s,%s,%s);", ts, band, c, pct(o), pct(n), pct(p), num(g), num(b), num(z))
	}
	function flush() { if (cs != "") keep(chan(cs), o, n, p, g, b, z); cs = "" }
	/during last scan/ { sec = 1; next }
	sec && /^[^ \t]/ && !/chanspec:|cca_/ { flush(); sec = 0 }   # the next heading ends it (lines may come unindented)
	sec && /chanspec:/ { flush(); blk = $0; cs = val("chanspec:"); g = val("crsglitch cnt:"); b = val("bad plcp:"); z = val("noise:"); o = n = p = ""; next }
	sec && /cca_/ { blk = blk " " $0; o = val("cca_obss:"); n = val("cca_nocat:"); p = val("cca_nopkt:"); next }
	!sec && ($1 == "chanspec" || $1 == "chspec") { delete col; for (i = 1; i <= NF; i++) col[$i] = i; tbl = ("obss" in col) && ("nocat" in col); ncol = NF; next }
	!sec && tbl && NF >= ncol - 1 && $1 !~ /^(version|state)/ {
		blk = $0
		keep(chan($1), $(col["obss"]), $(col["nocat"]), ("nopkt" in col) ? $(col["nopkt"]) : "", ("glitch" in col) ? $(col["glitch"]) : "",
			("badplcp" in col) ? $(col["badplcp"]) : "", ("knoise" in col) ? $(col["knoise"]) : "")
	}
	END {
		flush()
		if (raw != "") { for (i = 1; i <= k; i++) print out[i]; exit 0 }
		if (k < 2) exit 0
		print "BEGIN;"; for (i = 1; i <= k; i++) print out[i]; print "COMMIT;"
	}'
}

# The web page follows a scan through scanstate.htm: state running|done|error, a sequence number
# that goes up by one per scan, and each radio's result (ok, busy, empty, off).
scan_state() {   # state [bands-json] [message] [notes-json]
	wd=$(web_dir); mkdir -p "$wd"
	printf '{"state":"%s","seq":%s,"ts":%s,"bands":{%s},"notes":{%s},"msg":"%s"}\n' "$1" "${SCAN_SEQ:-0}" "$(now)" "$2" "$4" "$(js "$3")" \
		| write_atomic "$wd/scanstate.htm"
}
scan_next_seq() {
	mkdir -p "$TMPD"
	SCAN_SEQ=$(( $(cat "$TMPD/scan_seq" 2>/dev/null || echo 0) + 1 )); echo "$SCAN_SEQ" > "$TMPD/scan_seq"
}

# The driver keeps each channel's last figures between scans and overwrites only the channels a scan
# reaches, and on a busy channel it can stop a scan early (an RT-AX86U on 3004.388 reached 36-104 of
# 36-140 in the daytime). So compare the radio's list before and after: a channel whose figures changed
# was measured, and as scans go through the channels in order, so was every channel before it. A quiet
# channel can give the same figures twice, so one where the scan heard a network counts as reached too.
chanim_reached() {   # "channels in scan order" before-file after-file band ["channels heard"] -> "reached|not reached"
	parse_chanim_all 0 "$4" raw < "$2" > "$2.raw"
	parse_chanim_all 0 "$4" raw < "$3" > "$3.raw"
	awk -v order="$1" -v bf="$2.raw" -v af="$3.raw" -v heard="$5" 'BEGIN {
		while ((getline l < bf) > 0) { i = index(l, "\t"); B[substr(l, 1, i - 1)] = substr(l, i + 1) }
		while ((getline l < af) > 0) { i = index(l, "\t"); A[substr(l, 1, i - 1)] = substr(l, i + 1) }
		n = split(heard, HL, " "); for (i = 1; i <= n; i++) H[HL[i]] = 1
		k = split(order, O, " "); last = 0
		for (j = 1; j <= k; j++) if (((O[j] in A) && (!(O[j] in B) || A[O[j]] != B[O[j]])) || (O[j] in H)) last = j
		v = ""; r = ""
		for (j = 1; j <= k; j++) {
			if (j > last) r = r (r == "" ? "" : " ") O[j]
			else if (O[j] in A) v = v (v == "" ? "" : " ") O[j]
		}
		print v "|" r
	}'
	rm -f "$2.raw" "$3.raw"
}
# The primary channels of the networks in `wl scanresults` (stdin), one per line.
heard_channels() {
	awk '/^SSID: / { if (c != "") print c; c = ""; next }
		/^Mode: / && match($0, /Channel: (6g)?[0-9]+/) { t = substr($0, RSTART + 9, RLENGTH - 9); sub(/^6g/, "", t); c = t + 0; next }
		/Primary channel: / { t = $0; sub(/.*Primary channel: */, "", t); c = t + 0; next }
		END { if (c != "") print c }' | sort -un | tr '\n' ' '
}

# Finish a scan the driver stopped early: scan the channels it didn't reach. Appends what it hears to
# the scan's results and leaves the radio's list in after-file.
scan_rest() {   # ifc band "channels" before-file after-file results-file
	t0=$(now)
	until wl -i "$1" scan -c "$(echo $3 | tr ' ' ',')" > /dev/null 2>&1; do
		[ $(( $(now) - t0 )) -ge 10 ] && return 1
		sleep 2
	done
	t1=$(now); sleep 2
	while :; do   # done when the last channel has new figures (passive DFS channels take a moment each)
		wl -i "$1" chanim_stats all > "$5" 2>/dev/null
		p=$(chanim_reached "$3" "$4" "$5" "$2")
		[ -z "${p#*|}" ] && break
		[ $(( $(now) - t1 )) -ge 12 ] && break
		sleep 1
	done
	for i in 1 2 3; do
		if wl -i "$1" scanresults > "$TMPD/scan_rest.txt" 2>/dev/null; then cat "$TMPD/scan_rest.txt" >> "$6"; break; fi
		sleep 1
	done
	rm -f "$TMPD/scan_rest.txt"
	return 0
}

# Some drivers refuse a full scan but take one channel at a time: an RT-BE88U on a DFS channel took
# every single-channel scan, while an RT-AX88U and a GT-AX6000 took one only now and then (the GT-AX6000
# about every 16 s). So when the full scan is refused, scan the channels one by one, in order, waiting
# on each until the driver takes it. "Bad Channel" (a channel radar put off limits) is skipped. Stop when
# nothing has been taken for 60 s, or after 150 s; the next scan starts at the first channel not scanned,
# so the band is covered over a few scans. Sampling carries on meanwhile: each visit is a moment.
# Sets each_list (channels scanned), each_got (of those, measured), each_did, each_all, each_why (wl's
# last refusal) and each_more (1 if it stopped before the end of the band).
scan_each() {   # ifc band "channels" before-file after-file results-file
	each_list=""; each_got=""; each_did=0; each_why=""; each_more=""; : > "$6"
	nxt="$TMPD/each_$2.next"; err="$TMPD/scan_$2.err"; out="$TMPD/scan_$2.one"
	each_all=$(echo $3 | wc -w | tr -d ' ')
	off=$(cat "$nxt" 2>/dev/null); case "$off" in ''|*[!0-9]*) off=0 ;; esac
	[ "$off" -lt "$each_all" ] || off=0
	rm -f "$SCAN_FLAG"
	t0=$(now); last=$t0; adv=0
	for c in $(echo $3 | awk -v o="$off" '{ for (i = 0; i < NF; i++) printf "%s ", $((i + o) % NF + 1) }'); do
		ok=0
		while :; do
			if wl -i "$1" scan -c "$c" > /dev/null 2> "$err"; then ok=1; break; fi
			grep -q 'Bad Channel' "$err" && break
			[ $(( $(now) - last )) -ge 60 ] && break
			[ $(( $(now) - t0 )) -ge 150 ] && break
			sleep 2
		done
		if [ $ok = 0 ]; then
			if grep -q 'Bad Channel' "$err"; then each_why=$(wl_said "$err" 0 "refused"); adv=$((adv + 1)); continue; fi
			each_why=$(wl_said "$err" $(( $(now) - last )) "refused"); each_more=1; break
		fi
		last=$(now); p=""; sleep 1
		while :; do   # done when the channel has new figures or a network, or the results are in (drivers without figures)
			el=$(( $(now) - last ))
			if wl -i "$1" scanresults > "$out" 2>/dev/null; then
				wl -i "$1" chanim_stats all > "$5" 2>/dev/null
				p=$(chanim_reached "$c" "$4" "$5" "$2" "$(heard_channels < "$out")")
				[ -n "${p%%|*}" ] && break
				[ $el -ge 3 ] && break
			else : > "$out"
			fi
			[ $el -ge 10 ] && break
			sleep 1
		done
		cat "$out" >> "$6"
		adv=$((adv + 1)); each_did=$((each_did + 1)); each_list="$each_list${each_list:+ }$c"
		[ -n "${p%%|*}" ] && each_got="$each_got${each_got:+ }$c"
		[ -s "$5" ] && cp "$5" "$4"
		if [ $adv -lt "$each_all" ] && [ $(( $(now) - t0 )) -ge 150 ]; then each_more=1; break; fi
	done
	echo $(( (off + adv) % each_all )) > "$nxt"
	touch "$SCAN_FLAG"
	rm -f "$out"
}

scan() {   # [--delay]: a scheduled scan (cron), skipped when paused, off or in quiet hours
	sched=0; [ "$1" = "--delay" ] && sched=1
	if [ "$1" = "--delay" ]; then
		[ "$COLLECTION" = on ] || return 0
		if quiet_now; then log "scheduled scan skipped: quiet hours"; return 0; fi
	fi
	if ! ready; then
		scan_next_seq; scan_state error "" "Not ready: the clock isn't synced or the USB drive isn't mounted."
		say "Not ready (NTP not synced or USB storage missing)."; return 1
	fi
	lowprio
	mkdir -p "$TMPD"
	exec 7>"$TMPD/scan.lock"
	flock -n 7 || { say "A scan is already running."; return 0; }
	[ "$1" = "--delay" ] && sleep 8
	trap 'rm -f "$SCAN_FLAG"' EXIT; trap 'rm -f "$SCAN_FLAG"; exit 1' INT TERM HUP
	touch "$SCAN_FLAG"
	scan_next_seq; scan_state running
	ownf=$(own_ssids_file); bands=""; notes=""
	for r in $(radios); do
		ifc=$(nvram get wl${r}_ifname)
		hex=$(wl -i "$ifc" chanspec 2>/dev/null | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p')
		[ -n "$hex" ] || continue
		band=$(band_of_hex "$hex"); chs=$(radio_channels "$ifc" "$band")
		m0="$TMPD/chanim_$band.before"; m1="$TMPD/chanim_$band.after"; all="$TMPD/scan_$band.all"
		wl -i "$ifc" chanim_stats all > "$m0" 2>/dev/null   # the figures the radio still holds from earlier scans
		ts0=$(now); touch "$SCAN_FLAG"
		# a scheduled scan of a radio whose full scans are refused here: trickle scans it one channel at a
		# time, spread out; this only retries the full scan every 6 hours (scan_radio)
		set -- $(cat "$TMPD/refused_$band" 2>/dev/null); pre=0; [ "$1" = "$hex" ] && pre=1
		if [ $sched = 1 ] && [ $pre = 1 ] && [ $(( ts0 - ${2:-0} )) -lt 21600 ] 2>/dev/null; then
			result=ok; detail="one channel at a time, spread out (full scans refused on this channel)"
		else
			scan_radio "$ifc" "$band" "$hex"
		fi
		each=0
		# refused again at the 6-hour retry: trickle carries on (the first refusal still gets a burst, below)
		if [ "$result" = busy ] && [ $sched = 1 ] && [ $pre = 1 ]; then
			result=ok; detail="$detail; one channel at a time, spread out"
		elif [ "$result" = busy ] && [ -n "$chs" ]; then   # the full scan was refused: try one channel at a time
			full=$detail
			scan_each "$ifc" "$band" "$chs" "$m0" "$m1" "$all"
			if [ $each_did -gt 0 ]; then
				each=1; nn=$(grep '^BSSID' "$all" | awk '{ print $2 }' | sort -u | wc -l | tr -d ' ')
				detail="$nn network$( [ "$nn" = 1 ] || printf s) in $(( $(now) - ts0 )) s, one channel at a time (full scan refused: $full)"
				[ $each_did -lt $each_all ] && detail="$detail, $each_did of $each_all channels${each_why:+ ($each_why)}${each_more:+, the rest next time}"
				if [ "$nn" -gt 0 ] || [ -n "$each_got" ]; then result=ok; else result=empty; fi
			else
				detail="$detail; single channels refused too"
			fi
		fi
		case "$detail" in "one channel at a time, spread out"*|*"; one channel at a time, spread out") spread=1 ;; *) spread=0 ;; esac
		if [ "$result" = ok ] && [ $spread = 0 ]; then
			sts=$(now)
			if [ $each = 1 ]; then got=$each_got; covered=$each_list
			else
				cp "$res" "$all"
				wl -i "$ifc" chanim_stats all > "$m1" 2>/dev/null
				p=$(chanim_reached "$chs" "$m0" "$m1" "$band" "$(heard_channels < "$all")"); got=${p%%|*}; rest=${p#*|}
				# stopped early: scan the channels it didn't reach (twice at most), so every scan covers them all.
				# If that reached none of them, don't try the same channels again until a reboot.
				more=0; stop=${got##* }; skip="$TMPD/rest_$band.skip"; again=1
				[ -n "$rest" ] && [ "$(cat "$skip" 2>/dev/null)" = "$rest" ] && again=0
				while [ $again = 1 ] && [ -n "$got" ] && [ -n "$rest" ] && [ $more -lt 2 ]; do
					cp "$m1" "$m0"
					scan_rest "$ifc" "$band" "$rest" "$m0" "$m1" "$all" || break
					p=$(chanim_reached "$rest" "$m0" "$m1" "$band" "$(heard_channels < "$all")")
					if [ -z "${p%%|*}" ]; then [ $more -eq 0 ] && echo "$rest" > "$skip"; break; fi
					more=$((more + 1)); got="$got ${p%%|*}"; rest=${p#*|}
				done
				if [ $more -gt 0 ]; then
					nn=$(grep '^BSSID' "$all" | awk '{ print $2 }' | sort -u | wc -l | tr -d ' ')
					detail="$nn network$( [ "$nn" = 1 ] || printf s) in $(( $(now) - ts0 )) s, stopped at $stop and finished with $( [ $more = 1 ] && echo 'a second scan' || echo "$more more scans")"
				fi
				# store only the channels the scan covered, so the rest don't show up as empty and quiet
				# (no per-channel figures: no way to tell, so all of them, as before)
				if [ -n "$got" ]; then
					covered=$(echo "$chs|$rest" | awk -F'|' '{ n = split($2, R, " "); for (i = 1; i <= n; i++) X[R[i]] = 1
						m = split($1, C, " "); for (i = 1; i <= m; i++) if (!(C[i] in X)) printf "%s ", C[i] }')
				else covered=$chs
				fi
			fi
			parse_scan "$sts" "$band" "$covered" "$ownf" < "$all" | sql
			# what the radio measured on each channel this scan reached, where the driver reports it
			msql="$TMPD/chanim_$band.sql"
			parse_chanim_all "$sts" "$band" < "$m1" | awk -v got="$got" '
				BEGIN { n = split(got, G, " "); for (i = 1; i <= n; i++) K[G[i]] = 1 }
				/^INSERT/ { c = $0; sub(/^[^,]*,[^,]*,/, "", c); if (!((c + 0) in K)) next }
				{ print }' > "$msql"
			mc=$(grep -c '^INSERT' "$msql")
			if [ "$mc" -gt 0 ] 2>/dev/null && sql < "$msql"; then detail="$detail, $mc channels measured"; else mc=0; fi
			rm -f "$msql" "$m1" "$all"
			# the page says "starts with the next scan" until a scan has run with this version
			[ "$(cat "$DATA_DIR/measured_$band" 2>/dev/null)" = "$mc" ] || echo "$mc" > "$DATA_DIR/measured_$band"
		fi
		rm -f "$m0" "$m1" "$all"
		bands="$bands${bands:+,}\"$band\":\"$result\""
		notes="$notes${notes:+,}\"$band\":\"$(js "$detail")\""
		log "scan $band ($ifc): $result${detail:+, $detail}"
		say "  $band ($ifc): $result${detail:+, $detail}"
	done
	rm -f "$SCAN_FLAG"
	export_scans
	scan_state done "$bands" "" "$notes"
	flock -u 7
	log "scan complete"
}

# For radios whose full scans are refused (refused_<band> holds the current chanspec): scan one channel
# at a time, spread over the scan interval, instead of a burst of up to 150 s at every scheduled scan.
# cron runs this every 2 minutes; a band takes its next channel when it's due (the scan interval divided
# by its channels, at least 2 minutes). Each is one short trip off the router's channel: a fraction of a
# second's delay, no loss, in a ping test. A step is skipped while your own traffic is high (over 10% of
# the airtime in the latest sample), but not for longer than the scan interval; none run in quiet hours,
# or with scans paused or off. A sweep of the band is stored as one scan whose time moves forward with
# each channel, so the page shows it filling in; Scan now still scans the whole band at once.
trickle() {
	[ "$COLLECTION" = on ] && [ "$SCAN_INTERVAL" -gt 0 ] 2>/dev/null || return 0
	quiet_now && return 0
	ready || return 0
	mkdir -p "$TMPD"
	exec 7>"$TMPD/scan.lock"
	flock -n 7 || return 0
	lowprio
	ownf=""; did=0
	for r in $(radios); do
		ifc=$(nvram get wl${r}_ifname)
		hex=$(wl -i "$ifc" chanspec 2>/dev/null | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p')
		[ -n "$hex" ] || continue
		band=$(band_of_hex "$hex")
		set -- $(cat "$TMPD/refused_$band" 2>/dev/null)
		[ "$1" = "$hex" ] || continue   # full scans work on this channel (or haven't been refused)
		chs=$(radio_channels "$ifc" "$band"); nch=$(echo $chs | wc -w | tr -d ' ')
		[ "$nch" -gt 0 ] || continue
		t=$(now); lastf="$TMPD/trickle_$band.last"; last=$(cat "$lastf" 2>/dev/null); case "$last" in ''|*[!0-9]*) last=0 ;; esac
		gap=$((SCAN_INTERVAL * 60 / nch)); [ $gap -lt 120 ] && gap=120
		[ $((t - last)) -ge $((gap - 30)) ] || continue
		# your own traffic in the latest sample (transmit + receive from your clients), if it's recent
		own=$(sql "SELECT coalesce(tx, 0) + coalesce(inbss, 0) FROM samples WHERE band='$band' AND ts >= $((t - 180)) ORDER BY ts DESC LIMIT 1;")
		if [ "$(awk -v o="${own:-0}" 'BEGIN { print (o > 10) }')" = 1 ] && [ $((t - last)) -lt $((SCAN_INTERVAL * 60)) ]; then continue; fi
		nxt="$TMPD/each_$band.next"; off=$(cat "$nxt" 2>/dev/null); case "$off" in ''|*[!0-9]*) off=0 ;; esac
		[ "$off" -lt "$nch" ] || off=0
		c=$(echo $chs | cut -d' ' -f$((off + 1)))
		m0="$TMPD/chanim_$band.t0"; m1="$TMPD/chanim_$band.t1"; out="$TMPD/scan_$band.one"; err="$TMPD/scan_$band.err"
		wl -i "$ifc" chanim_stats all > "$m0" 2>/dev/null
		if ! wl -i "$ifc" scan -c "$c" > /dev/null 2> "$err"; then
			grep -q 'Bad Channel' "$err" && echo $(( (off + 1) % nch )) > "$nxt"   # radar put it off limits: next one
			rm -f "$m0"; continue   # refused: the same channel next time
		fi
		t2=$(now); echo "$t2" > "$lastf"; p=""; sleep 1
		while :; do   # done when the channel has new figures or a network, or the results are in
			el=$(( $(now) - t2 ))
			if wl -i "$ifc" scanresults > "$out" 2>/dev/null; then
				wl -i "$ifc" chanim_stats all > "$m1" 2>/dev/null
				p=$(chanim_reached "$c" "$m0" "$m1" "$band" "$(heard_channels < "$out")")
				[ -n "${p%%|*}" ] && break
				[ $el -ge 3 ] && break
			else : > "$out"
			fi
			[ $el -ge 10 ] && break
			sleep 1
		done
		# this sweep so far moves to now, and this channel joins it (a new sweep at the start of the band)
		sw="$TMPD/sweep_$band"; sts=$(cat "$sw" 2>/dev/null); case "$sts" in ''|*[!0-9]*) sts="" ;; esac
		[ "$off" = 0 ] && sts=""
		[ -n "$sts" ] && [ $((t2 - sts)) -gt $((SCAN_INTERVAL * 120)) ] && sts=""   # a sweep left for too long: start afresh
		[ -n "$ownf" ] || ownf=$(own_ssids_file)
		{
			echo "BEGIN;"
			[ -n "$sts" ] && for tb in scans aps chanim; do echo "UPDATE $tb SET ts=$t2 WHERE band='$band' AND ts=$sts;"; done
			echo "COMMIT;"
			echo "DELETE FROM scans WHERE band='$band' AND ts=$t2 AND ch=$c;"
			parse_scan "$t2" "$band" "$c" "$ownf" < "$out"
			[ -n "${p%%|*}" ] && parse_chanim_all "$t2" "$band" < "$m1" | awk -v c="$c" '/^INSERT/ { x = $0; sub(/^[^,]*,[^,]*,/, "", x); if ((x + 0) != c) next } { print }' | sed 's/^INSERT INTO chanim/INSERT OR REPLACE INTO chanim/'
			echo "DELETE FROM aps WHERE band='$band' AND ts=$t2 AND rowid NOT IN (SELECT max(rowid) FROM aps WHERE band='$band' AND ts=$t2 GROUP BY bssid);"
		} | sql
		echo "$t2" > "$sw"
		off=$(( (off + 1) % nch )); echo "$off" > "$nxt"
		mc=$(sql "SELECT count(*) FROM chanim WHERE band='$band' AND ts=$t2;")
		[ "$(cat "$DATA_DIR/measured_$band" 2>/dev/null)" = "$mc" ] || echo "$mc" > "$DATA_DIR/measured_$band"
		if [ "$off" = 0 ]; then   # the band is done: one line in the syslog per sweep
			nn=$(sql "SELECT count(DISTINCT bssid) FROM aps WHERE band='$band' AND ts=$t2;")
			log "scan $band ($ifc): one channel at a time, spread out: $(sql "SELECT count(*) FROM scans WHERE band='$band' AND ts=$t2;") channels, $nn network$( [ "$nn" = 1 ] || printf s), $mc channels measured"
			rm -f "$sw"
		fi
		rm -f "$m0" "$m1" "$out"
		did=1
	done
	[ $did = 1 ] && export_scans
	return 0
}

wl_said() {   # errfile seconds fallback -> 'wl said "Not Ready" for 45 s', or 'fallback after 45 s'
	m=$(head -1 "$1" 2>/dev/null | tr -d '\r"' | sed 's/^wl: //' | cut -c1-60)
	if [ -n "$m" ]; then printf 'wl said "%s" for %s s' "$m" "$2"; else printf '%s after %s s' "$3" "$2"; fi
}

# One radio's neighbour scan. Sets result (ok, busy, empty or off) and detail; the results are in $res.
# The driver answers "Not Ready" until the scan ends, so poll for the results instead of guessing how
# long a scan takes: 2.4 GHz scans take a few seconds, 5 GHz ones longer (more channels, and DFS channels
# are listened to rather than probed), and much longer on some drivers (3006.102 / 17.10).
scan_radio() {   # ifc band chanspec
	result=ok; detail=""; res="$TMPD/scan_$2.txt"; err="$TMPD/scan_$2.err"; : > "$res"
	if [ "$(wl -i "$1" isup 2>/dev/null)" != "1" ]; then result=off; return 0; fi
	# The radio refuses a scan while it's already scanning (Smart Connect, AiMesh, acsd): retry for up to 20 s.
	# Some drivers refuse every full scan on a DFS channel ("Scan Rejected"): after that, on the same
	# chanspec, try once and go straight to one channel at a time; retry for the full 20 s every 6 hours.
	t0=$(now); rf="$TMPD/refused_$2"; quick=0
	set -- "$1" "$2" "$3" $(cat "$rf" 2>/dev/null)
	[ -n "$3" ] && [ "$4" = "$3" ] && [ $(( t0 - ${5:-0} )) -lt 21600 ] 2>/dev/null && quick=1
	until wl -i "$1" scan > /dev/null 2> "$err"; do
		if [ $quick = 1 ]; then result=busy; detail=$(wl_said "$err" 0 "refused" | sed 's/ for 0 s$/ again/'); return 0; fi
		if [ $(( $(now) - t0 )) -ge 20 ]; then
			result=busy; detail=$(wl_said "$err" 20 "still busy")
			[ -n "$3" ] && grep -q 'Scan Rejected' "$err" && echo "$3 $(now)" > "$rf"
			return 0
		fi
		sleep 2
	done
	rm -f "$rf"
	limit=45; [ "$2" = 2g ] && limit=20
	t1=$(now); sleep 3
	while :; do
		el=$(( $(now) - t1 ))
		if wl -i "$1" scanresults > "$res" 2> "$err"; then
			if grep -q '^BSSID' "$res"; then
				nn=$(grep -c '^BSSID' "$res"); detail="$nn network$( [ "$nn" = 1 ] || printf s) in ${el} s"; return 0
			fi
			# Finished with nothing heard, or a driver that answers before the scan ends: give it 12 s.
			if [ $el -ge 12 ]; then result=empty; detail="no networks heard in ${el} s"; return 0; fi
		fi
		if [ $el -ge $limit ]; then
			result=empty; detail=$(wl_said "$err" "$el" "no results"); return 0
		fi
		sleep 2
	done
}

# A scan pauses sampling; a flag left behind by a killed scan is ignored after 5 minutes.
scanning() {
	[ -f "$SCAN_FLAG" ] || return 1
	ft=$(date -r "$SCAN_FLAG" +%s 2>/dev/null) || return 1
	[ $(( $(now) - ft )) -lt 300 ]
}

# ---- quiet hours ----------------------------------------------------------------
# QUIET marks the half hours of the week with no scheduled scans: 336 bits, Monday 00:00-00:30
# first and Sunday 23:30-24:00 last, four to a hex digit, most significant bit first. So each
# day is 12 digits, and each digit is 2 hours. Times are the router's local time. Empty = none.
quiet_at() {   # weekday (0 = Sunday, as date +%w) hour minute -> true if that half hour is quiet
	[ -n "$QUIET" ] || return 1
	awk -v q="$QUIET" -v w="$1" -v h="${2#0}" -v m="${3#0}" 'BEGIN {
		s = ((w + 6) % 7) * 48 + h * 2 + (m >= 30)
		d = index("0123456789abcdef", substr(q, int(s / 4) + 1, 1)) - 1
		exit (int(d / substr("8421", s % 4 + 1, 1)) % 2) ? 0 : 1
	}'
}
quiet_now() { set -- $(date '+%w %H %M'); quiet_at "$1" "$2" "$3"; }

quiet_text() {   # e.g. "Mon-Fri 18:00-24:00; Sat-Sun 09:00-12:00, 18:00-24:00"
	[ -n "$QUIET" ] || { say none; return 0; }
	awk -v q="$QUIET" 'function hm(s) { return sprintf("%02d:%02d", int(s / 2), s % 2 * 30) }
	BEGIN {
		split("Mon Tue Wed Thu Fri Sat Sun", D, " ")
		for (d = 0; d < 7; d++) {
			r = ""; st = -1
			for (s = 0; s <= 48; s++) {
				on = 0
				if (s < 48) {
					i = d * 48 + s
					x = index("0123456789abcdef", substr(q, int(i / 4) + 1, 1)) - 1
					on = int(x / substr("8421", i % 4 + 1, 1)) % 2
				}
				if (on && st < 0) st = s
				if (!on && st >= 0) { r = r (r == "" ? "" : ", ") hm(st) "-" hm(s); st = -1 }
			}
			R[d] = r
		}
		out = ""; d = 0
		while (d < 7) {
			e = d
			while (e < 6 && R[e + 1] == R[d]) e++
			if (R[d] != "") out = out (out == "" ? "" : "; ") (e > d ? D[d + 1] "-" D[e + 1] : D[d + 1]) " " R[d]
			d = e + 1
		}
		print (out == "" ? "none" : out)
	}'
}

collection_text() {
	case "$COLLECTION" in
		off)    say "off: no samples or scheduled scans (Scan now still works)" ;;
		paused) say "scans paused: samples every $SAMPLE_INTERVAL s, no scheduled scans (Scan now still works)" ;;
		*)      if [ "$SCAN_INTERVAL" -gt 0 ] 2>/dev/null; then
				say "on: samples every $SAMPLE_INTERVAL s, neighbour scans every $SCAN_INTERVAL min$( [ -n "$QUIET" ] && printf ' outside quiet hours')"
			else
				say "on: samples every $SAMPLE_INTERVAL s, neighbour scans off"
			fi ;;
	esac
}

# ---- export (JSON files read by the web page) -------------------------------
# httpd runs .htm/.js files through its <% %> / <# #> template engine, so no '<' may reach
# the page raw. In this JSON '<' can only occur inside strings (SSIDs), where < is identical.
write_atomic() {   # file content-from-stdin
	tmp="$1.$$.tmp"
	if sed 's/</\\u003c/g' > "$tmp"; then mv -f "$tmp" "$1"; else rm -f "$tmp"; return 1; fi
}

# The radio's regulatory country (wl country: "E0 (E0/887) ...", "US (US/0) ...") and ASUS's territory
# code ("EU/01"), so the page can mark the weather-radar channels with the rules that apply there.
country_code() {
	for r in $(radios); do
		cc=$(wl -i "$(nvram get wl${r}_ifname)" country 2>/dev/null | awk 'NR == 1 { print $1 }')
		case "$cc" in [A-Z0-9#][A-Z0-9]) printf '%s' "$cc"; return ;; esac
	done
}
territory_code() { t=$(nvram get territory_code); case "$t" in [A-Z][A-Z]/*|[A-Z][A-Z]) printf '%s' "$t" ;; esac; }

radios_json() {
	first=1; printf '['
	for r in $(radios); do
		ifc=$(nvram get wl${r}_ifname)
		up=$(wl -i "$ifc" isup 2>/dev/null)
		csl=$(wl -i "$ifc" chanspec 2>/dev/null)
		cs=${csl%% *}
		hex=$(printf '%s' "$csl" | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p')
		[ -n "$hex" ] || continue
		band=$(band_of_hex "$hex"); width=$(width_of_hex "$hex"); center=$(( hex & 0xff ))
		noise=$(jnum "$(wl -i "$ifc" noise 2>/dev/null)")
		dfs=$(wl -i "$ifc" dfs_status 2>/dev/null)
		dstate=$(printf '%s' "$dfs" | sed -n 's/^state \(.*\) time elapsed.*/\1/p')
		dms=$(printf '%s' "$dfs" | sed -n 's/.*time elapsed \([0-9]*\)ms.*/\1/p')
		auto=false; [ "$(nvram get wl${r}_chanspec)" = "0" ] && auto=true
		[ $first -eq 1 ] || printf ','; first=0
		printf '{"radio":%s,"iface":"%s","band":"%s","up":%s,"cs":"%s","hex":"%s","ctl":%s,"width":%s,"center":%s,"noise":%s,"auto":%s,"dfs_state":"%s","dfs_ms":%s,"channels":[%s]}' \
			"$r" "$(js "$ifc")" "$band" "$([ "$up" = 1 ] && echo true || echo false)" "$(js "$cs")" "$hex" \
			"$(jnum "$(ctl_of_cs "$cs")")" "$(jnum "$width")" "$(jnum "$center")" "$noise" "$auto" "$(js "$dstate")" "$(jnum "$dms")" \
			"$(radio_channels "$ifc" "$band" | sed 's/ /,/g')"
	done
	printf ']'
}

export_live() {
	wd=$(web_dir); mkdir -p "$wd"
	t=$(now); since=$((t - 86400)); evsince=$((t - 30 * 86400))
	mkdir -p "$TMPD"; ownj=""
	while IFS= read -r o; do ownj="$ownj${ownj:+,}\"$(js "$o")\""; done < "$(own_ssids_file)"
	dbb=$(ls -l "$DB" 2>/dev/null | awk '{print $5}')
	mj=""   # channels measured in each band's last scan; none yet: no scan since this version
	for b in 2g 5g 6g; do [ -f "$DATA_DIR/measured_$b" ] && mj="$mj${mj:+,}\"$b\":$(jnum "$(cat "$DATA_DIR/measured_$b")")"; done
	{
		printf '{"version":"%s","generated":%s,"sample_interval":%s,"scan_interval":%s,"retain_days":%s,' \
			"$VERSION" "$t" "$SAMPLE_INTERVAL" "$SCAN_INTERVAL" "$RETAIN_DAYS"
		printf '"data_dir":"%s","db_bytes":%s,"fs":"%s","fs_note":"%s","own_ssids":[%s],"extra_own":"%s",' \
			"$(js "$DATA_DIR")" "$(jnum "$dbb")" "$(js "$(fstype_of "$DATA_DIR")")" "$(js "$(journal_note "$DATA_DIR")")" "$ownj" "$(js "$EXTRA_OWN_SSIDS")"
		printf '"collection":"%s","quiet":"%s","tz_off":%s,"build":"%s",' "$COLLECTION" "$QUIET" "$(tz_off)" "$(js "$( [ -f "$BUILD_FILE" ] && awk '$1 == "dev" { print $2 "@" $3 }' "$BUILD_FILE")")"
		printf '"measured":{%s},"country":"%s","territory":"%s","radios":%s,' "$mj" "$(js "$(country_code)")" "$(js "$(territory_code)")" "$(radios_json)"
		printf '"damaged":%s,"samples":' "$(jnum "$(cat "$DATA_DIR/damaged" 2>/dev/null)")"   # when sqlite first said the database is damaged; null = fine
		json_out '{}' "SELECT json_group_object(band, json(a)) FROM (SELECT band, json_group_array(json_array(ts,obss,nocat,tx,inbss,idle,glitch,noise,ctl,width,center,nopkt,doze,txop,goodtx,badtx,badplcp,knoise)) AS a FROM (SELECT * FROM samples WHERE ts>=$since ORDER BY band, ts) GROUP BY band);"
		printf ',"events":'
		json_out '[]' "SELECT json_group_array(json_array(ts,band,tag,old,new,detail)) FROM (SELECT * FROM events WHERE ts>=$evsince ORDER BY ts DESC LIMIT 500);"
		printf '}\n'
	} | write_atomic "$wd/live.htm"
}

# Local UTC offset in seconds, so day/hour buckets line up with the router's clock (e.g. +0200 -> 7200).
tz_off() {
	z=$(date +%z 2>/dev/null); case "$z" in [+-][0-9][0-9][0-9][0-9]) ;; *) echo 0; return ;; esac
	h=${z#?}; m=${h#??}; h=${h%??}; o=$(( (1$h - 100) * 3600 + (1$m - 100) * 60 ))
	case "$z" in -*) echo $(( -o )) ;; *) echo "$o" ;; esac
}

# Airtime averages per time bucket: [b, obss, nocat, yours, idle, max(obss+nocat), glitch, badplcp,
# noise, nopkt, tx, inbss, goodtx, badtx]. b is the bucket start, aligned to local time.
samples_agg() {   # days bucket-seconds -> JSON on stdout ({} if the DB is busy)
	asince=$(( $(now) - $1 * 86400 )); B=$2; aoff=$(tz_off)
	json_out '{}' "SELECT json_group_object(band, json(a)) FROM (SELECT band, json_group_array(json_array(b, o, n, u, i, m, g, bp, nz, np, tx, ib, gt, bt)) AS a FROM (SELECT band, ((ts+$aoff)/$B)*$B-$aoff AS b, round(avg(obss),1) AS o, round(avg(nocat),1) AS n, round(avg(tx+inbss),1) AS u, round(avg(idle),1) AS i, max(obss+nocat) AS m, round(avg(glitch)) AS g, round(avg(badplcp)) AS bp, round(avg(noise),1) AS nz, round(avg(nopkt),1) AS np, round(avg(tx),1) AS tx, round(avg(inbss),1) AS ib, round(avg(goodtx),1) AS gt, round(avg(badtx),1) AS bt FROM samples WHERE ts>=$asince GROUP BY band, b ORDER BY band, b) GROUP BY band);"
}

export_week() {   # 7 days in 15-minute buckets
	wd=$(web_dir); mkdir -p "$wd"; t=$(now)
	{ printf '{"generated":%s,"bucket":900,"agg":' "$t"; samples_agg 7 900; printf '}\n'; } | write_atomic "$wd/week.htm"
}

# 30 days: airtime in 1-hour buckets, and channel scans in 6-hour buckets
# ([b, ch, avg score, max networks, strongest, avg own, scans]) for the 30-day heatmap and channel load.
export_month() {
	wd=$(web_dir); mkdir -p "$wd"; t=$(now); since=$((t - 30 * 86400)); off=$(tz_off)
	{
		printf '{"generated":%s,"bucket":3600,"agg":' "$t"
		samples_agg 30 3600
		printf ',"scan_bucket":21600,"scans":'
		json_out '{}' "SELECT json_group_object(band, json(a)) FROM (SELECT band, json_group_array(json(CASE WHEN mn = 0 THEN json_array(b, ch, sc, ap, be, ow, n) ELSE json_array(b, ch, sc, ap, be, ow, n, mo, mc, mp, mz, mg, mn) END)) AS a FROM (SELECT s.band, ((s.ts+$off)/21600)*21600-$off AS b, s.ch, round(avg(s.score),1) AS sc, max(s.aps) AS ap, max(s.best) AS be, round(avg(s.own),1) AS ow, count(*) AS n, round(avg(m.obss),1) AS mo, round(avg(m.nocat),1) AS mc, round(avg(m.nopkt),1) AS mp, round(avg(m.noise)) AS mz, round(avg(m.glitch)) AS mg, count(m.obss) AS mn FROM scans s LEFT JOIN chanim m ON m.band=s.band AND m.ts=s.ts AND m.ch=s.ch WHERE s.ts>=$since GROUP BY s.band, b, s.ch ORDER BY s.band, b, s.ch) GROUP BY band);"
		printf '}\n'
	} | write_atomic "$wd/month.htm"
}

export_scans() {
	wd=$(web_dir); mkdir -p "$wd"
	t=$(now); since=$((t - 7 * 86400))
	{
		printf '{"generated":%s,"scan_interval":%s,"last_scan":' "$t" "$SCAN_INTERVAL"
		json_out '{}' "SELECT json_group_object(band, mt) FROM (SELECT band, max(ts) AS mt FROM scans GROUP BY band);"
		printf ',"scans":'
		# [ts, ch, estimate, networks, strongest, own] and, where the radio measured the channel,
		# [..., 1, others, non-Wi-Fi, unclassified, noise, glitches]
		json_out '{}' "SELECT json_group_object(band, json(a)) FROM (SELECT band, json_group_array(json(CASE WHEN obss IS NULL THEN json_array(ts,ch,score,aps,best,own) ELSE json_array(ts,ch,score,aps,best,own,1,obss,nocat,nopkt,noise,glitch) END)) AS a FROM (SELECT s.ts, s.band, s.ch, s.score, s.aps, s.best, s.own, m.obss, m.nocat, m.nopkt, m.noise, m.glitch FROM scans s LEFT JOIN chanim m ON m.band=s.band AND m.ts=s.ts AND m.ch=s.ch WHERE s.ts>=$since ORDER BY s.band, s.ts, s.ch) GROUP BY band);"
		printf ',"aps":'
		# The networks of the latest scan, and, for channels it didn't cover (a scan that took one channel at
		# a time, or stopped early), those of the newest scan in the last 6 hours that did. Each with its time.
		t6=$((t - 6 * 3600))
		json_out '{}' "SELECT json_group_object(band, json(a)) FROM (SELECT x.band, json_group_array(json_object('ssid',x.ssid,'bssid',x.bssid,'rssi',x.rssi,'ctl',x.ctl,'center',x.center,'width',x.width,'util',x.util,'own',x.own,'phy',x.phy,'sec',x.sec,'snr',x.snr,'ts',x.ts)) AS a FROM (SELECT * FROM (SELECT u.*, row_number() OVER (PARTITION BY u.band, u.bssid ORDER BY u.ts DESC) AS rn FROM (SELECT p.* FROM aps p JOIN (SELECT band, ch, max(ts) AS ct FROM scans WHERE ts>=$t6 GROUP BY band, ch) c ON p.band=c.band AND p.ctl=c.ch AND p.ts=c.ct UNION SELECT p.* FROM aps p JOIN (SELECT band, max(ts) AS mt FROM aps GROUP BY band) l ON p.band=l.band AND p.ts=l.mt) u) WHERE rn=1 ORDER BY band, rssi DESC) x GROUP BY x.band);"
		printf '}\n'
	} | write_atomic "$wd/scans.htm"
}

export_all() { export_live; export_week; export_month; export_scans; }

# ---- scheduled entry points --------------------------------------------------
collect() {
	[ "$COLLECTION" = off ] && return 0   # return, not exit: install calls this too
	ready || exit 0
	lowprio
	mkdir -p "$TMPD"
	exec 6>"$TMPD/collect.lock"
	flock -n 6 || exit 0   # previous run still busy, or prune/VACUUM running: skip this minute
	t0=$(now)
	detect_restart
	detect_radar
	scanning || sample_all
	if [ "$1" != "--once" ] && [ "$SAMPLE_INTERVAL" -lt 60 ]; then
		left=$(( t0 + SAMPLE_INTERVAL - $(now) ))
		[ "$left" -gt 0 ] && sleep "$left"
		scanning || sample_all
	fi
	export_live
	wd=$(web_dir)
	if [ $(( $(date +%M | sed 's/^0//') % 15 )) -eq 0 ] || [ ! -f "$wd/week.htm" ]; then export_week; fi
	if [ "$(date +%M)" = "05" ] || [ ! -f "$wd/month.htm" ]; then export_month; fi   # hourly
	[ -f "$wd/scans.htm" ] || export_scans   # after a reboot, before the first scan
	return 0
}

prune() {
	ready || exit 0
	lowprio
	mkdir -p "$TMPD"
	exec 6>"$TMPD/collect.lock"
	# Wait (up to 2 min) for the current collect, then hold sampling off while we run.
	# BusyBox flock has no -w, so poll with -n.
	i=0; until flock -n 6; do i=$((i + 1)); [ $i -gt 60 ] && exit 0; sleep 2; done
	t=$(now); cut=$((t - RETAIN_DAYS * 86400)); evcut=$((t - 365 * 86400))
	sql "DELETE FROM samples WHERE ts<$cut; DELETE FROM scans WHERE ts<$cut; DELETE FROM chanim WHERE ts<$cut; DELETE FROM aps WHERE ts<$cut; DELETE FROM events WHERE ts<$evcut; PRAGMA optimize;"
	# Once a week, compact the file, but only when a quarter or more of it is free pages: it rewrites the
	# whole file, which is the riskiest write if the power goes. Its temporary copy goes on the same drive,
	# not in /tmp (the router's RAM).
	if [ "$(date +%w)" = "0" ]; then
		fl=$(sql "PRAGMA freelist_count;"); pc=$(sql "PRAGMA page_count;")
		if [ "${fl:-0}" -gt 0 ] 2>/dev/null && [ $((fl * 4)) -ge "${pc:-0}" ]; then
			SQLITE_TMPDIR="$DATA_DIR" "$SQLITE" -batch -cmd ".timeout 8000" "$DB" "VACUUM;" && log "database compacted ($fl of $pc pages were free)"
		fi
	fi
	export_all
}

# ---- web UI (Merlin Addons API) ------------------------------------------------
menu_remount() {
	umount "$MENUTREE" 2>/dev/null
	mount -o bind "$TMP_MENUTREE" "$MENUTREE"
}

is_ours() { [ "$(cat "$WWW_USER/${1%.asp}.title" 2>/dev/null)" = "$TITLE" ]; }

# Pick a page slot: keep our previous slot if it's still free (stable URL), otherwise the
# first free userN.asp. Slots are identified as ours by their .title file; taken slots are skipped.
find_webui_page() {
	am_webui_page=none
	prev=$(cat "$ADDON_DIR/webui_page" 2>/dev/null)
	if [ -n "$prev" ] && { [ ! -f "$WWW_USER/$prev" ] || is_ours "$prev"; }; then
		am_webui_page=$prev; return
	fi
	i=1
	while [ $i -le 20 ]; do
		p="user$i.asp"
		if [ -f "$WWW_USER/$p" ]; then
			is_ours "$p" && { am_webui_page=$p; return; }
		elif [ "$am_webui_page" = none ]; then
			am_webui_page=$p
		fi
		i=$((i + 1))
	done
}

mount_webui() {
	[ -d "$WWW_USER" ] || { say "$WWW_USER not found - is this Asuswrt-Merlin with JFFS scripts enabled?"; return 1; }
	exec 9>"$WEBUI_LOCK"; flock -x 9 2>/dev/null
	find_webui_page
	if [ "$am_webui_page" = "none" ]; then
		flock -u 9; say "No free web UI slot (Merlin allows 20 addon pages)."; log "no free webui page"; return 1
	fi
	# drop any other slot we held before (only if it is still ours)
	for f in "$WWW_USER"/user*.title; do
		[ -f "$f" ] || continue
		p="$(basename "$f" .title).asp"
		[ "$p" != "$am_webui_page" ] && is_ours "$p" && rm -f "$WWW_USER/$p" "$f"
	done
	cp -f "$PAGE_SRC" "$WWW_USER/$am_webui_page"
	echo "$TITLE" > "$WWW_USER/${am_webui_page%.asp}.title"
	[ "$(cat "$ADDON_DIR/webui_page" 2>/dev/null)" = "$am_webui_page" ] || echo "$am_webui_page" > "$ADDON_DIR/webui_page"
	# Menu: edit a copy, and only swap it in if the result is exactly one new line (ours) at a
	# known anchor. A broken menuTree.js would break the router's whole menu, so never risk it.
	[ -f "$TMP_MENUTREE" ] || cp -f "$MENUTREE" "$TMP_MENUTREE"
	new="$TMP_MENUTREE.$NAME.$$"
	sed "/tabName: \"$TITLE\"/d" "$TMP_MENUTREE" > "$new"
	before=$(wc -l < "$new")
	entry="{url: \"$am_webui_page\", tabName: \"$TITLE\"},"
	# Wireless -> after "Professional" (Advanced_WAdvanced_Content.asp); Merlin's Tools menu as a fallback
	where=""
	for a in "Advanced_WAdvanced_Content.asp:Wireless" "Tools_OtherSettings.asp:Tools"; do
		anchor=${a%%:*}
		if [ "$(grep -c "url: \"$anchor\"" "$new")" = "1" ]; then
			sed -i "/url: \"$anchor\"/a $entry" "$new"; where=${a#*:}; break
		fi
	done
	if [ -n "$where" ] && [ "$(grep -c "tabName: \"$TITLE\"" "$new")" = "1" ] && [ "$(wc -l < "$new")" -eq $((before + 1)) ]; then
		mv -f "$new" "$TMP_MENUTREE"
		menu_remount
		echo "$where" > "$TMPD/menu_where"
	else
		rm -f "$new" "$TMPD/menu_where"
		say "Couldn't add the menu entry safely, so the menu was left alone. Open http://$(nvram get lan_ipaddr)/$am_webui_page instead."
		log "menu entry not added (unexpected menuTree.js); page at $am_webui_page"
	fi
	flock -u 9
	log "web UI mounted as $am_webui_page"
}

unmount_webui() {
	page=$(cat "$ADDON_DIR/webui_page" 2>/dev/null)
	exec 9>"$WEBUI_LOCK"; flock -x 9 2>/dev/null
	if [ -f "$TMP_MENUTREE" ]; then
		sed -i "/tabName: \"$TITLE\"/d" "$TMP_MENUTREE"
		menu_remount
	fi
	[ -n "$page" ] && is_ours "$page" && rm -f "$WWW_USER/$page" "$WWW_USER/${page%.asp}.title"
	flock -u 9
}

web_assets() {
	wd=$(web_dir); mkdir -p "$wd"
	[ -f "$ADDON_DIR/chart.umd.min.js" ] && cp -f "$ADDON_DIR/chart.umd.min.js" "$wd/chart.umd.min.js"
}

# Collection on: sample, scan and prune. Scans paused: no scan job. Off: no jobs at all, so
# history stays exactly as it was until collection is switched back on.
# Quiet hours don't change the jobs: a scheduled scan checks them when it starts.
cron_add() {
	if [ "$COLLECTION" = off ]; then cron_del; return 0; fi
	cru a "${NAME}_collect" "* * * * * $SCRIPT collect"
	if [ "$COLLECTION" = on ] && [ "$SCAN_INTERVAL" -gt 0 ] 2>/dev/null; then
		if [ "$SCAN_INTERVAL" -ge 60 ]; then
			cru a "${NAME}_scan" "7 */$((SCAN_INTERVAL / 60)) * * * $SCRIPT scan --delay"
		else
			cru a "${NAME}_scan" "*/$SCAN_INTERVAL * * * * $SCRIPT scan --delay"
		fi
		cru a "${NAME}_trickle" "*/2 * * * * $SCRIPT trickle"   # does nothing unless a radio refuses full scans
	else
		cru d "${NAME}_scan" 2>/dev/null; cru d "${NAME}_trickle" 2>/dev/null
	fi
	cru a "${NAME}_prune" "23 4 * * * $SCRIPT prune"
}

cron_del() {
	for j in collect scan trickle prune; do cru d "${NAME}_$j" 2>/dev/null; done
}

hook_add() {   # file line
	f="$SCRIPTS_DIR/$1"
	[ -s "$f" ] || printf '#!/bin/sh\n' > "$f"   # missing or empty
	head -1 "$f" | grep -q '^#!' || sed -i '1i #!/bin/sh' "$f"
	hook_del "$1"
	[ -n "$(tail -c 1 "$f")" ] && echo >> "$f"   # never glue onto a last line with no newline
	printf '%s # %s\n' "$2" "$NAME" >> "$f"
	chmod 755 "$f"
}

hook_del() {   # only lines this addon wrote: start with our script path, end with our tag
	f="$SCRIPTS_DIR/$1"
	[ -f "$f" ] && sed -i "\\|^$SCRIPT .*# $NAME\$|d" "$f"
	return 0
}

startup() {
	mkdir -p "$TMPD"
	[ -x "$SQLITE" ] && [ -d "$DATA_DIR" ] && init_db   # adds anything new after an update
	mount_webui
	web_assets
	cron_add
	ready && export_all
	return 0
}

apply_settings() {   # values saved from the web page via Merlin's custom settings
	[ -f "$HELPER" ] || return 1
	. "$HELPER"
	v=$(am_settings_get ${NAME}_sample); case "$v" in 30|60) SAMPLE_INTERVAL=$v ;; esac
	v=$(am_settings_get ${NAME}_scan); case "$v" in 0|15|30|60|120|180|360) SCAN_INTERVAL=$v ;; esac
	v=$(am_settings_get ${NAME}_retain); case "$v" in 7|14|30|60|90|180) RETAIN_DAYS=$v ;; esac
	v=$(am_settings_get ${NAME}_ownssids)
	EXTRA_OWN_SSIDS=$(printf '%s' "$v" | tr -d '"$`\\')
	v=$(am_settings_get ${NAME}_mode); case "$v" in on|paused|off) COLLECTION=$v ;; esac
	v=$(am_settings_get ${NAME}_quiet)   # exactly 84 hex digits, or it's left unchanged
	case "${#v}:$v" in
		84:*[!0-9a-f]*) ;;
		84:*) case "$v" in *[!0]*) QUIET=$v ;; *) QUIET="" ;; esac ;;
	esac
	write_conf
	cron_add
	ready && export_all
	log "settings updated: collection=$COLLECTION sample=$SAMPLE_INTERVAL scan=$SCAN_INTERVAL retain=$RETAIN_DAYS quiet=$(quiet_text)"
}

service_event() {   # action service
	[ "$1" = "start" ] || return 0
	case "$2" in ${NAME}*) lowprio ;; *) return 0 ;; esac
	case "$2" in
		${NAME}scan) scan ;;
		${NAME}config) apply_settings ;;
		${NAME}refresh) ready && { sample_all; export_all; } ;;
	esac
}

# ---- install / uninstall ------------------------------------------------------
write_conf() {
	cat > "$CONF" <<EOF
# WiFi Insight settings - run "$SCRIPT startup" after editing
SAMPLE_INTERVAL=$SAMPLE_INTERVAL      # seconds between interference samples (30 or 60)
SCAN_INTERVAL=$SCAN_INTERVAL        # minutes between neighbour scans, 0 = off
RETAIN_DAYS=$RETAIN_DAYS          # days of history to keep
EXTRA_OWN_SSIDS="$EXTRA_OWN_SSIDS"     # extra SSIDs to treat as yours, separated by |
COLLECTION=$COLLECTION          # on, paused (no scheduled scans) or off (no samples or scans)
# Quiet hours (no scheduled scans): one bit per half hour, Monday 00:00 first, 12 hex digits
# a day, 84 in all; easiest to set on the Settings page. Empty = none.
QUIET="$QUIET"
AMTM_UPDATE=$AMTM_UPDATE         # on: amtm may update WiFi Insight (amtmupdate); off: only 'update' does
DATA_DIR="$DATA_DIR"
SQLITE="$SQLITE"
EOF
}

# ---- support check (read-only: changes nothing on the router) ------------------
ck_ok()   { say "  [ OK ] $*"; }
ck_warn() { say "  [WARN] $*"; }
ck_fail() { say "  [FAIL] $*"; ck_fails=$((ck_fails + 1)); }

nearest_dir() {   # $1 or its nearest existing parent; "/" if nothing on the way exists
	d=$1
	while [ ! -d "$d" ] && [ "$d" != "/" ] && [ -n "$d" ]; do
		[ -L "$d" ] && { echo /; return; }   # broken link, e.g. /opt while Entware's USB drive isn't mounted
		d=$(dirname "$d")
	done
	echo "${d:-/}"
}
free_kb() { df -Pk "$(nearest_dir "$1")" 2>/dev/null | awk 'NR == 2 { print $4 }'; }
# KB -> MB in awk: Merlin's shell arithmetic is 32-bit, so $((kb / 1024)) goes negative past 2 TiB free.
# ([ -lt ] is fine: its test handles 64-bit numbers.)
kb_to_mb() { awk -v k="${1:-0}" 'BEGIN { print int(k / 1024) }'; }
fstype_of() {   # filesystem type of the mount holding $1 (longest matching mount point)
	p=$(readlink -f "$(nearest_dir "$1")" 2>/dev/null)
	awk -v p="${p:-/}" '{
		m = $2; ok = (m == "/" || p == m || index(p, m "/") == 1)
		if (ok && length(m) >= best) { best = length(m); t = $3 }
	} END { print t }' "${WI_MOUNTS:-/proc/mounts}" 2>/dev/null
}
# A filesystem without a journal (ext2, FAT, exFAT, NTFS, HFS, or ext4 made without one, which amtm
# offers): a power cut while it's writing can leave files damaged, the history database included.
# A mounted ext3/ext4 with a journal has /proc/fs/jbd2/<device>-8.
fs_dev() { p=$(readlink -f "$(nearest_dir "$1")" 2>/dev/null); awk -v p="${p:-/}" '{ m = $2; if ((m == "/" || p == m || index(p, m "/") == 1) && length(m) >= best) { best = length(m); d = $1 } } END { print d }' "${WI_MOUNTS:-/proc/mounts}" 2>/dev/null; }
no_journal() {   # path -> what to call its filesystem if it has no journal ("ext2, which has no journal"), else nothing
	t=$(fstype_of "$1")
	case "$t" in
		ext2|vfat|msdos|fat|exfat|texfat|ntfs|ntfs3|tntfs|ufsd|tfat|hfs|hfsplus|thfsplus|fuseblk) echo "$t, which has no journal" ;;
		ext3|ext4) j="${WI_PROC:-/proc}/fs/jbd2"; d=$(fs_dev "$1")
			[ -d "$j" ] && [ -n "$d" ] && [ ! -d "$j/${d##*/}-8" ] && echo "$t without a journal" ;;
	esac
	return 0
}
journal_note() { n=$(no_journal "$1"); [ -n "$n" ] && echo "The drive is $n, so a power cut while it's writing can damage the history database. ext4 with a journal is safer (amtm can format a USB drive that way)."; }

check_support() {
	ck_fails=0
	say "Checking that this router can run $TITLE:"

	# Firmware: Asuswrt-Merlin with the Addons API (custom pages, settings, service events)
	if [ "$(uname -o 2>/dev/null)" = "ASUSWRT-Merlin" ]; then
		ck_ok "Asuswrt-Merlin $(fw_version)"
	else
		ck_fail "Not Asuswrt-Merlin firmware. Stock ASUS firmware can't run addons."
	fi
	if [ -f "$HELPER" ] && grep -q 'am_settings_get' "$HELPER" 2>/dev/null && [ -e "$WWW_USER" ] && [ -f "$MENUTREE" ]; then
		ck_ok "Addons API (web pages and settings)"
	else
		ck_fail "This firmware has no Addons API. Update to Asuswrt-Merlin 386 or 388."
	fi

	# Broadcom driver with per-channel airtime statistics
	if ! have wl; then
		ck_fail "No Broadcom Wi-Fi driver ('wl' not found in $PATH). Only Broadcom-based models are supported."
	else
		good=0; seen=0; off=0; bands=""
		for r in $(radios); do
			ifc=$(nvram get wl${r}_ifname); seen=1
			cl=$(wl -i "$ifc" chanspec 2>/dev/null); cs=${cl%% *}
			hex=$(printf '%s\n' "$cl" | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p')
			case "$([ -n "$hex" ] && band_of_hex "$hex")" in 2g) b="2.4 GHz" ;; 5g) b="5 GHz" ;; 6g) b="6 GHz" ;; *) b="radio $r" ;; esac
			bands="$bands|$b"
			if [ "$(wl -i "$ifc" isup 2>/dev/null)" != "1" ]; then
				ck_warn "$b ($ifc) is switched off. It will be monitored once it's on."
				off=$((off + 1)); continue
			fi
			out=$(wl -i "$ifc" chanim_stats 2>&1)
			hdr=$(printf '%s\n' "$out" | grep -E '^(chanspec|chspec)[[:space:]]' | head -1)
			missing=""
			for col in tx inbss obss nocat idle; do
				case " $(printf '%s' "$hdr" | tr -s ' \t' '  ') " in *" $col "*) ;; *) missing="$missing $col" ;; esac
			done
			if [ -z "$hdr" ]; then
				said=$(printf '%s\n' "$out" | grep -v '^version' | grep -v '^$' | head -1 | cut -c1-60)
				ck_warn "$b ($ifc) doesn't report airtime statistics (wl chanim_stats${said:+ said: $said})."
			elif [ -n "$missing" ]; then ck_warn "$b ($ifc) airtime statistics lack:$missing"
			# Read a row exactly as sampling will, so a layout it can't read is caught here,
			# not by charts that stay empty after installing.
			elif ! printf '%s\n' "$out" | parse_chanim "$cs" "$hex" > /dev/null; then
				ck_warn "$b ($ifc) reports airtime statistics in a layout WiFi Insight can't read yet. Please report it with the output of 'debug'."
			else ck_ok "$b ($ifc) airtime statistics"; good=$((good + 1))
			fi
		done
		# History is kept per band, so two radios on one band (5 GHz-1 + 5 GHz-2, or two 6 GHz)
		# would overwrite each other, and only wl0-wl2 are read. Refuse those layouts for now.
		dup=$(printf '%s\n' "$bands" | tr '|' '\n' | grep -v '^$' | sort | uniq -d | head -1)
		if [ -n "$(nvram get wl3_ifname)" ]; then
			ck_fail "This router has four radios. WiFi Insight supports up to three, one per band, for now."
		elif [ -n "$dup" ]; then
			ck_fail "This router has two $dup radios. WiFi Insight can't keep their data apart yet."
		fi
		if [ $seen -eq 0 ]; then ck_fail "No Wi-Fi radios found."
		elif [ $good -eq 0 ] && [ $off -gt 0 ]; then ck_fail "No Wi-Fi radio is switched on, so support can't be checked. Turn one on and try again."
		elif [ $good -eq 0 ]; then ck_fail "No radio provides the airtime statistics WiFi Insight is built on."
		fi
	fi

	# Shell tools the addon relies on (router BusyBox builds vary)
	t="$ROOT/tmp/$NAME.selftest.$$"; printf 'ab' > "$t" 2>/dev/null; lack=""
	[ "$(tail -c 1 "$t" 2>/dev/null)" = "b" ] || lack="$lack tail-c"
	date -r "$t" +%s >/dev/null 2>&1 || lack="$lack date-r"
	[ "$(date -u -d @86400 +%Y%m%d 2>/dev/null)" = "19700102" ] || lack="$lack date-d"
	[ -n "$(readlink -f "$ROOT/tmp" 2>/dev/null)" ] || lack="$lack readlink-f"
	[ "$(printf 'x\n' | sed 's/x/y/')" = "y" ] && [ "$(echo 1 | awk '{ print toupper("a") $1 + 1 }')" = "A2" ] || lack="$lack sed/awk"
	[ "$(printf 'a\tb' | tr -d '\000-\037')" = "ab" ] || lack="$lack tr"
	for p in flock md5sum cru; do have "$p" || lack="$lack $p"; done
	rm -f "$t"
	if [ -z "$lack" ]; then ck_ok "Shell tools (BusyBox)"
	else ck_fail "This firmware's BusyBox lacks:$lack"
	fi

	# Entware + sqlite3 with JSON on persistent storage
	if [ -x "$SQLITE" ]; then
		if [ "$("$SQLITE" :memory: 'SELECT json_array(1);' 2>/dev/null)" = "[1]" ]; then ck_ok "sqlite3 with JSON support"
		else ck_fail "sqlite3 has no JSON support. Run: opkg update && opkg upgrade sqlite3-cli"
		fi
	elif [ -x "$ROOT/opt/bin/opkg" ]; then
		ck_fail "sqlite3 isn't installed. Run: opkg update && opkg install sqlite3-cli"
	else
		ck_fail "Entware isn't installed. It needs a USB drive; amtm can set it up for you."
	fi
	nd=$(nearest_dir "$DATA_DIR"); fst=$(fstype_of "$DATA_DIR"); kb=$(free_kb "$DATA_DIR")
	[ "$nd" = "/" ] && fst=""   # nothing on the way exists, e.g. the USB drive isn't mounted
	case "$(readlink -f "$nd" 2>/dev/null)/:$fst" in
		"$ROOT/jffs/"*|*:jffs2|*:ubifs|*:yaffs2)
			ck_fail "History folder $DATA_DIR is on the router's flash. Constant writes would wear it out; use the USB drive." ;;
		*:|*:tmpfs|*:ramfs|*:rootfs|*:devtmpfs|*:squashfs)
			ck_fail "History folder $DATA_DIR isn't on a USB drive (it would live in RAM and vanish at reboot)." ;;
		*)
			if [ "${kb:-0}" -lt 51200 ]; then ck_fail "Less than 50 MB free for history in $DATA_DIR."
			else ck_ok "History storage: $DATA_DIR ($fst, $(kb_to_mb "$kb") MB free)"
			fi
			n=$(journal_note "$DATA_DIR"); [ -n "$n" ] && ck_warn "History storage: $n" ;;
	esac

	# JFFS (addon files) and a free web UI slot
	jkb=$(free_kb "$ROOT/jffs")
	if [ ! -d "$ROOT/jffs" ]; then ck_fail "The JFFS partition isn't available."
	elif [ "${jkb:-0}" -lt 1024 ]; then ck_fail "Less than 1 MB free on JFFS."
	else ck_ok "JFFS space ($(kb_to_mb "$jkb") MB free)"
	fi
	find_webui_page
	if [ "$am_webui_page" = none ]; then
		ck_fail "No free addon page slot (all 20 are used by other addons)."
	else
		ck_ok "Addon page slot: $am_webui_page"
	fi

	# Not blockers
	[ "$(nvram get jffs2_scripts)" = "1" ] || ck_warn "'JFFS custom scripts and configs' is off. Install will switch it on."
	[ "$(nvram get ntp_ready)" = "1" ] || ck_warn "The clock isn't synced yet. Collection starts once it is."

	say ""
	if [ $ck_fails -gt 0 ]; then say "This router can't run $TITLE ($ck_fails problem(s) above)."; return 1; fi
	say "This router can run $TITLE."
	return 0
}

install() {
	src="$(cd "$(dirname "$0")" && pwd)"
	say "Installing $TITLE $VERSION"
	say ""
	check_support || die "Nothing was installed or changed."
	say ""
	if [ "$(nvram get jffs2_scripts)" != "1" ]; then
		nvram set jffs2_scripts=1; nvram commit
		say "Enabled 'JFFS custom scripts and configs' (needed so the addon survives reboots)."
	fi
	mkdir -p "$ADDON_DIR" "$SCRIPTS_DIR" "$TMPD"
	if [ "$src" != "$ADDON_DIR" ]; then
		asp="$src/$NAME.asp"
		if ! asp_matches "$asp"; then   # missing, or left over from another version
			say "Downloading the web page from GitHub..."
			asp="$TMPD/$NAME.asp.dl"; got=0
			# 1) the release tag for this exact version (tags never change), 2) main, 3) the latest release
			if [ -n "$WI_RAW_URL" ]; then bases="$RAW_URL"; else bases="$RAW_BASE/$VERSION $RAW_URL"; fi
			for base in $bases release; do
				[ "$base" = release ] && { base=$(release_url); [ -n "$base" ] || continue; }
				if fetch "$base/$NAME.asp" "$asp" quiet; then
					asp_matches "$asp" && { got=1; break; }
				fi
			done
			[ $got -eq 1 ] || { rm -f "$asp"; die "Couldn't get $NAME.asp $VERSION. Put it in the same folder as $NAME.sh and run install again."; }
		fi
		# rename into place: a running copy of the old script (e.g. during update) keeps reading its own file
		cp -f "$src/$NAME.sh" "$SCRIPT.new" && mv -f "$SCRIPT.new" "$SCRIPT"
		cp -f "$asp" "$PAGE_SRC.new" && mv -f "$PAGE_SRC.new" "$PAGE_SRC"
		rm -f "$TMPD/$NAME.asp.dl"
		[ -f "$src/chart.umd.min.js" ] && cp -f "$src/chart.umd.min.js" "$ADDON_DIR/"
	fi
	chmod 755 "$SCRIPT"
	# A development version says so (update_dev sets WI_BUILD); anything else installed is a release.
	if [ -n "$WI_BUILD" ]; then printf '%s\n' "$WI_BUILD" > "$BUILD_FILE"; else rm -f "$BUILD_FILE"; fi
	grep -q '^AMTM_UPDATE=' "$CONF" 2>/dev/null || write_conf   # new, or from before 1.2.0: add the new settings
	. "$CONF"; DB="$DATA_DIR/$NAME.db"
	mkdir -p "$DATA_DIR" || die "Couldn't create $DATA_DIR"
	init_db || die "Couldn't create the database in $DATA_DIR"
	cj="$ADDON_DIR/chart.umd.min.js"
	if [ -s "$cj" ] && ! chart_ok "$cj"; then rm -f "$cj"; fi   # replace a copy that doesn't match
	if [ ! -s "$cj" ]; then
		say "Downloading Chart.js..."
		if curl -fsL --retry 2 "$CHART_URL" -o "$cj.dl" && chart_ok "$cj.dl"; then
			mv -f "$cj.dl" "$cj"
		else
			rm -f "$cj.dl"; say "Couldn't download a verified Chart.js; the page will load it from the CDN instead."
		fi
	fi
	hook_add services-start "$SCRIPT startup &"
	hook_add service-event "$SCRIPT service_event \"\$@\" &"
	startup
	if ready; then
		collect --once
		if [ "$(sql "SELECT count(*) FROM scans;" 2>/dev/null)" = "0" ]; then
			say "Running the first neighbour scan (Wi-Fi may hiccup for a second)..."
			scan
		else
			say "Kept your history: neighbour scans carry on as scheduled."   # an update: no extra scan
		fi
	else
		say "Storage or NTP not ready yet - collection will start automatically."
	fi
	page=$(cat "$ADDON_DIR/webui_page" 2>/dev/null)
	where=$(cat "$TMPD/menu_where" 2>/dev/null)
	say ""
	if [ -n "$where" ]; then
		say "Done. Open the router UI -> $where -> $TITLE"
		say "(If the tab isn't there, reload the page with Ctrl+F5 / Cmd+Shift+R: browsers cache the menu.)"
	else
		say "Done."
	fi
	[ -n "$page" ] && say "Direct link: http://$(nvram get lan_ipaddr)/$page"
	say "The interference chart fills in over the next few minutes."
	# The install command downloads to /tmp/wifiinsight.sh: remove that copy, so it can't be run by
	# mistake later (an old copy's 'scan' or 'status' runs old code).
	[ "$0" = "$ROOT/tmp/$NAME.sh" ] && [ "$0" != "$SCRIPT" ] && rm -f "$0"
	return 0
}

asp_matches() { [ -s "$1" ] && grep -q "wifiinsight-version: $VERSION " "$1"; }

# Download $1 to $2 [quiet]. Up to 3 attempts; succeeds only if a non-empty file arrived,
# otherwise says why. (A router's /tmp is shared RAM, so a write can fail now and work a moment later.)
fetch() {
	for attempt in 1 2 3; do
		rm -f "$2" 2>/dev/null; mkdir -p "$(dirname "$2")"
		code=$(curl -sL --retry 2 --connect-timeout 15 -w '%{http_code}' -o "$2" "$1" 2>/dev/null); rc=$?
		if [ $rc -eq 23 ]; then why="couldn't write $2, $(df -k "$(dirname "$2")" 2>/dev/null | awk 'NR == 2 { print $4 }') KB free"
		elif [ $rc -ne 0 ]; then why="curl error $rc"
		elif [ "$code" != "200" ]; then why="HTTP $code"
		elif [ ! -s "$2" ]; then why="empty response"
		else return 0
		fi
		[ "$code" = "404" ] && break   # won't change on retry
		[ $attempt -lt 3 ] && sleep 2
	done
	[ "$3" = quiet ] || say "  download failed ($why): $1"
	rm -f "$2" 2>/dev/null; return 1
}

# The newest published release's version (its tag), so update and install only ever get a
# released version, never work merged to main but not yet released. Asks GitHub's API first,
# then github.com's releases/latest redirect (no API rate limit). Prints nothing if both fail.
latest_tag() {
	t=$(curl -fsL --retry 2 --connect-timeout 15 -H 'Accept: application/vnd.github+json' \
		"https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
		| sed -n 's/.*"tag_name": *"\([0-9][0-9.]*\)".*/\1/p' | head -1)
	[ -n "$t" ] || t=$(curl -fsI --retry 2 --connect-timeout 15 -o /dev/null -w '%{redirect_url}' \
		"https://github.com/$REPO/releases/latest" 2>/dev/null \
		| sed -n 's#.*/releases/tag/\([0-9][0-9.]*\)$#\1#p')
	echo "$t"
}
# Raw URL of the files in the newest release (a tag: the script and the page always match).
release_url() {
	[ -n "$WI_RAW_URL" ] && { echo "$RAW_URL"; return; }
	t=$(latest_tag); [ -n "$t" ] && echo "$RAW_BASE/$t"
}
# True if version $1 is newer than $2 (1.0.10 > 1.0.9).
ver_gt() {
	awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
		for (i = 1; i <= n; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
		exit 1 }'
}

update() {   # [force]  fetch the latest release from GitHub and reinstall over this one
	dl="$TMPD/update.$$"; rm -rf "$dl"; mkdir -p "$dl" || die "Couldn't create $dl"
	say "Checking GitHub for updates..."
	rel=$(release_url)
	[ -n "$rel" ] || { rm -rf "$dl"; die "Couldn't find the latest release on GitHub (no connection to github.com?); nothing was changed."; }
	fetch "$rel/$NAME.sh" "$dl/$NAME.sh" || { rm -rf "$dl"; die "Couldn't download the update; nothing was changed."; }
	new=$(sed -n 's/^VERSION="\([0-9][0-9.]*\)".*/\1/p' "$dl/$NAME.sh" | head -1)
	if [ -z "$new" ] || ! sh -n "$dl/$NAME.sh" 2>/dev/null; then
		rm -rf "$dl"; die "The downloaded script looks incomplete; nothing was changed."
	fi
	if [ "$new" = "$VERSION" ] && [ "$1" != "force" ] && [ ! -f "$BUILD_FILE" ]; then
		rm -rf "$dl"; say "Already up to date ($VERSION)."; return 0
	fi
	if ver_gt "$VERSION" "$new" && [ "$1" != "force" ]; then
		rm -rf "$dl"
		say "This is $VERSION$( [ -f "$BUILD_FILE" ] && printf ' (a development version)'), newer than the latest release ($new). Nothing was changed; 'update force' installs $new."
		return 0
	fi
	if ! fetch "$rel/$NAME.asp" "$dl/$NAME.asp" || ! grep -q "wifiinsight-version: $new " "$dl/$NAME.asp"; then
		rm -rf "$dl"; die "Couldn't download the matching web page; nothing was changed."
	fi
	say "Updating $VERSION -> $new (settings and history are kept)"
	sh "$dl/$NAME.sh" install; rc=$?
	rm -rf "$dl"
	[ $rc -eq 0 ] && rm -f "$BUILD_FILE"   # a release now, whatever that release's installer knows
	return $rc
}

# Development versions: the newest code on a GitHub branch (main by default), to try changes before
# they're released. The files come from the branch's current commit, so the script and the page
# always match. Unreleased code can be broken; plain 'update' goes back to the latest release.
build_text() {   # "" for a release; "development version: main @ 1a2b3c4, installed 2026-11-09 23:30"
	[ -f "$BUILD_FILE" ] || return 0
	read -r kind br sha when < "$BUILD_FILE"
	[ "$kind" = dev ] && printf 'development version: %s @ %s, installed %s' "$br" "$sha" "$when"
}
update_dev() {   # [branch]
	br=${1:-main}
	case "$br" in ''|[-./]*|*..*|*//*|*/|*[!A-Za-z0-9._/-]*|refs/*|pull/*) die "'$br' isn't a branch name; nothing was changed." ;; esac
	dl="$TMPD/update.$$"; rm -rf "$dl"; mkdir -p "$dl" || die "Couldn't create $dl"
	say "Looking up the newest commit on $br..."
	# Only a branch of this repository, by its commit. GitHub also serves commits and pull requests
	# from other people's forks under this repository's addresses, and those aren't reviewed here.
	sha=$(curl -fsL --retry 2 --connect-timeout 15 -H 'Accept: application/vnd.github+json' \
		"https://api.github.com/repos/$REPO/branches/$br" 2>/dev/null \
		| grep -o '"sha": *"[0-9a-f]\{40\}"' | head -1 | grep -o '[0-9a-f]\{40\}')
	if [ -z "$sha" ]; then
		rm -rf "$dl"; die "GitHub has no branch '$br' in $REPO, or couldn't be reached; nothing was changed."
	fi
	ref=$sha
	if ! fetch "$RAW_BASE/$ref/$NAME.sh" "$dl/$NAME.sh" quiet; then
		rm -rf "$dl"; die "Couldn't download $NAME.sh from the branch '$br' (no connection to GitHub?); nothing was changed."
	fi
	new=$(sed -n 's/^VERSION="\([0-9][0-9.]*\)".*/\1/p' "$dl/$NAME.sh" | head -1)
	if [ -z "$new" ] || ! sh -n "$dl/$NAME.sh" 2>/dev/null; then
		rm -rf "$dl"; die "The script on '$br' looks incomplete; nothing was changed."
	fi
	if ! fetch "$RAW_BASE/$ref/$NAME.asp" "$dl/$NAME.asp" quiet || ! grep -q "wifiinsight-version: $new " "$dl/$NAME.asp"; then
		rm -rf "$dl"; die "Couldn't download the matching web page from '$br'; nothing was changed."
	fi
	short=$(printf '%s' "$sha" | cut -c1-7)
	say "Installing the development version of $br ($new, commit $short). Settings and history are kept;"
	say "'$SCRIPT update' goes back to the latest release."
	b="dev $br $short $(date '+%Y-%m-%d %H:%M')"
	WI_BUILD="$b" sh "$dl/$NAME.sh" install; rc=$?
	rm -rf "$dl"
	if [ $rc -eq 0 ]; then
		printf '%s\n' "$b" > "$BUILD_FILE"   # also when that branch's installer predates WI_BUILD
		log "development version installed: $br @ $short ($new)"
	fi
	return $rc
}

uninstall() {
	say "Removing $TITLE"
	cron_del
	unmount_webui
	hook_del services-start
	hook_del service-event
	[ -f "$ROOT/jffs/addons/custom_settings.txt" ] && sed -i "/^${NAME}_/d" "$ROOT/jffs/addons/custom_settings.txt"
	rm -rf "$(web_dir)" "$TMPD" "$SCAN_FLAG"
	if [ "$1" = "--keep-data" ]; then
		say "History kept in $DATA_DIR"
	else
		case "$DATA_DIR" in */$NAME) rm -rf "$DATA_DIR" ;; *) rm -f "$DB" "$DB.bad" "$DATA_DIR/damaged"; say "Left $DATA_DIR in place (deleted only the database)." ;; esac
	fi
	rm -rf "$ADDON_DIR"
	say "Removed."
}

status() {
	say "$TITLE $VERSION$(b=$(build_text); [ -n "$b" ] && printf ' (%s)' "$b")"
	say "Data:        $DB ($( [ -f "$DB" ] && du -h "$DB" | cut -f1 || echo missing))"
	n=$(journal_note "$DATA_DIR"); say "Storage:     $(fstype_of "$DATA_DIR")${n:+. $n}"
	say "Web page:    $(cat "$ADDON_DIR/webui_page" 2>/dev/null || echo 'not mounted')"
	say "Ready:       $(ready && echo yes || echo 'no (NTP or storage)')"
	say "Collection:  $(collection_text)"
	say "Quiet hours: $(quiet_text)$(quiet_now && printf ' (quiet now)')$( [ -n "$QUIET_BAD" ] && printf ' (the QUIET line in the config is invalid, so it is ignored)')"
	say "amtm updates: $AMTM_UPDATE"
	say "Cron:";  cru l 2>/dev/null | grep "$NAME" | sed 's/^/  /'
	if [ -f "$DB" ]; then
		t=$(now)
		sql "SELECT '  ' || band || ': ' || count(*) || ' samples, last ' || ($t - max(ts)) || 's ago' FROM samples GROUP BY band;"
		sql "SELECT '  last scan: ' || ($t - max(ts)) || 's ago' FROM scans;"
		say "Recent events:"
		sql "SELECT '  ' || datetime(ts,'unixepoch','localtime') || '  ' || band || '  ' || tag || '  ' || coalesce(old,'') || ' -> ' || coalesce(new,'') FROM events ORDER BY ts DESC LIMIT 8;"
	fi
	if [ -f "$DATA_DIR/damaged" ]; then
		say "Database:    DAMAGED (noticed $(date -d "@$(cat "$DATA_DIR/damaged")" '+%Y-%m-%d %H:%M' 2>/dev/null || echo earlier)). Run '$SCRIPT repair'."
	fi
}

# Rebuild a damaged database from everything still readable (sqlite3 .dump; .recover isn't in every
# build), with sampling and scans held off meanwhile. The damaged copy is kept next to it as .bad.
repair() {   # [force]: rebuild even when the check finds nothing wrong
	[ -x "$SQLITE" ] || die "sqlite3 isn't installed ($SQLITE)."
	[ -f "$DB" ] || die "There's no database at $DB."
	mkdir -p "$TMPD"
	exec 7>"$TMPD/scan.lock"
	i=0; until flock -n 7; do i=$((i + 1)); [ $i -gt 150 ] && die "A scan is still running. Try again in a few minutes."; sleep 2; done
	exec 6>"$TMPD/collect.lock"
	i=0; until flock -n 6; do i=$((i + 1)); [ $i -gt 60 ] && die "Sampling is still running. Try again in a minute."; sleep 2; done
	say "Checking $DB (a minute or so on a large one)..."
	# the full check: quick_check doesn't compare indexes with their tables, and that's damage too
	chk=$("$SQLITE" "$DB" "PRAGMA integrity_check;" 2>&1 | head -3)
	if [ "$chk" = ok ] && [ "$1" != force ]; then
		rm -f "$DATA_DIR/damaged"; say "The database is fine: nothing to repair."; return 0
	fi
	[ "$chk" = ok ] || say "It's damaged: $(printf '%s' "$chk" | head -1 | cut -c1-100)"
	kb=$(du -k "$DB" | cut -f1); free=$(df -k "$DATA_DIR" | tail -1 | awk '{ print $(NF-2) }')
	[ "$free" -gt $((kb * 2)) ] 2>/dev/null || die "Not enough free space on the drive for a copy (${kb} KB needed twice); nothing was changed."
	new="$DB.new"; bad="$DB.bad"; rm -f "$new" "$new-journal"
	say "Copying everything still readable into a new database..."
	"$SQLITE" "$DB" .dump 2>/dev/null | sed 's/^ROLLBACK;.*/COMMIT;/' | "$SQLITE" "$new" > /dev/null 2>&1
	nchk=$("$SQLITE" "$new" "PRAGMA integrity_check;" 2>&1 | head -1)
	[ "$nchk" = ok ] || { rm -f "$new"; die "The new copy isn't sound either ($nchk); nothing was changed."; }
	rm -f "$bad" "$bad-journal"
	mv "$DB" "$bad" || { rm -f "$new"; die "Couldn't move the damaged database aside; nothing was changed."; }
	[ -f "$DB-journal" ] && mv "$DB-journal" "$bad-journal"
	mv "$new" "$DB" || { mv "$bad" "$DB"; die "Couldn't put the new copy in place; the database is as it was."; }
	init_db   # tables or indexes the damage took
	rm -f "$DATA_DIR/damaged"
	kept=$(sql "SELECT (SELECT count(*) FROM samples) || ' samples and ' || (SELECT count(DISTINCT band || ts) FROM scans) || ' scans';")
	say "Repaired: kept $kept. The damaged copy is $bad: delete it once everything looks right."
	log "database repaired, kept $kept; the damaged copy is $bad"
}

fw_version() {   # e.g. 3004.388.12_2
	fw=$(nvram get buildno); ext=$(nvram get extendno); fv=$(nvram get firmver | tr -d .)
	[ -n "$ext" ] && fw="${fw}_$ext"; [ -n "$fv" ] && fw="$fv.$fw"
	echo "$fw"
}

# Everything a bug report or router report needs, and nothing personal: no network names, no MAC
# addresses, no IP addresses. Works without installing (sh /tmp/wifiinsight.sh debug).
debug() {
	say "$TITLE $VERSION$(b=$(build_text); [ -n "$b" ] && printf ' (%s)' "$b")"
	say "Router:      $(nvram get productid) $(nvram get odmpid)  firmware $(fw_version)  $(uname -m)"
	say "BusyBox:     $(busybox 2>/dev/null | head -1 | cut -d' ' -f2)   sqlite3: $("$SQLITE" --version 2>/dev/null | cut -d' ' -f1)"
	say "Smart Connect: $(nvram get smart_connect_x)   wl_ifnames: $(nvram get wl_ifnames)   country: $(country_code)  territory: $(territory_code)"
	say "acsd: $(pidof acsd2 acsd || echo 'not running')"
	say "Collection: $(collection_text)"
	say "Quiet hours: $(quiet_text)"
	say "Storage: $DATA_DIR on $(fstype_of "$DATA_DIR")"
	for r in 0 1 2 3; do
		ifc=$(nvram get wl${r}_ifname)
		[ -n "$ifc" ] || continue
		say "===== wl$r ($ifc)  nband=$(nvram get wl${r}_nband) nband_type=$(nvram get wl${r}_nband_type) ====="
		wl -i "$ifc" ver 2>/dev/null | sed -n '2p'
		wl -i "$ifc" isup; wl -i "$ifc" chanspec; wl -i "$ifc" noise
		wl -i "$ifc" chanim_stats; wl -i "$ifc" dfs_status; wl -i "$ifc" channels
		say "nvram chanspec=$(nvram get wl${r}_chanspec) bw=$(nvram get wl${r}_bw)"
	done
}

# ---- collection switch, amtm and the menu ----------------------------------------
set_collection() {   # on|paused|off, as Settings -> Collection on the page
	case "$1" in on|paused|off) ;; *) die "Collection can be on, paused or off." ;; esac
	COLLECTION=$1
	write_conf
	if [ -f "$HELPER" ]; then . "$HELPER"; am_settings_set ${NAME}_mode "$1" 2>/dev/null; fi   # what the page saves
	cron_add
	ready && export_live
	log "collection set to $1 from the command line"
	say "Collection: $(collection_text)"
}

# amtm (the Asuswrt-Merlin Terminal Menu) updates scripts that answer "amtmupdate". It runs
# "amtmupdate check" (exit 0: amtm may update it, 1: the user turned that off), and when a newer
# release is out, "amtmupdate", expecting a line or two and exit 0 on success, 1 on failure.
amtm_update() {   # [check]
	if [ "$1" = check ]; then [ "$AMTM_UPDATE" = on ]; return; fi
	if [ "$AMTM_UPDATE" != on ]; then
		say "  ✖  $TITLE: updates through amtm are turned off (AMTM_UPDATE=off). '$SCRIPT update' still works."
		return 1
	fi
	say "  i  Running function amtmupdate"
	mkdir -p "$TMPD"; alog="$TMPD/amtmupdate.log"
	( update ) > "$alog" 2>&1; rc=$?
	now_ver=$(sed -n 's/^VERSION="\([0-9][0-9.]*\)".*/\1/p' "$SCRIPT" 2>/dev/null | head -1)
	if [ $rc -eq 0 ]; then
		say "  ✔  $TITLE ${now_ver:-$VERSION} amtmupdate complete"
		log "amtmupdate: $VERSION -> ${now_ver:-$VERSION}"
	else
		why=$(grep -v '^[[:space:]]*$' "$alog" | tail -1 | sed 's/^ERROR: //' | cut -c1-100)
		say "  ✖  $TITLE amtmupdate failed: ${why:-no output} (details in $alog)"
		log "amtmupdate failed: $why"
	fi
	return $rc
}

usage() {
	say "Usage: $0 [menu] | install | check | update [force | dev [branch]] | uninstall [--keep-data] | status | scan |"
	say "       collection [on|paused|off] | repair | debug | amtmupdate [check] | export | version"
}
menu_pause() { printf '\n Press Enter to go back to the menu '; read -r dummy || exit 0; }
menu_collection() {
	say " Collection is $COLLECTION."
	say "  1  On: samples, and scans on schedule outside quiet hours"
	say "  2  Scans paused: keeps sampling, no scheduled scans"
	say "  3  Off: no sampling or scans; the page, settings and history stay"
	say "  e  Back"
	printf '\n Choose an option: '; read -r c || return 0
	case "$c" in
		1) set_collection on ;; 2) set_collection paused ;; 3) set_collection off ;;
		*) return 0 ;;
	esac
	menu_pause
}
menu_uninstall() {   # true once removed
	printf ' Remove %s? Type yes to confirm: ' "$TITLE"; read -r a || return 1
	if [ "$a" != yes ]; then say " Nothing was removed."; menu_pause; return 1; fi
	printf ' Keep the history database, for a later reinstall? (y/n) '; read -r k
	case "$k" in [yY]*) uninstall --keep-data ;; *) uninstall ;; esac
	return 0
}
# Run with no arguments in a terminal (which is how amtm opens it). Each action runs in a subshell,
# so one that stops with an error returns to the menu instead of closing it.
menu() {
	while :; do
		have clear && clear
		page=$(cat "$ADDON_DIR/webui_page" 2>/dev/null)
		say ""
		say " $TITLE $VERSION${page:+   (Wireless > $TITLE, $page)}"
		b=$(build_text); [ -n "$b" ] && say " This is a $b"
		say " Collection:   $(collection_text)"
		say " Quiet hours:  $(quiet_text)$(quiet_now && printf ' (quiet now; set them on the Settings page)')"
		say " amtm updates: $AMTM_UPDATE"
		say ""
		say "  1  Status"
		say "  2  Scan now"
		say "  3  Collection: on, scans paused or off"
		say "  4  Update to the latest release"
		say "  5  Reinstall the latest release"
		say "  6  Debug report, for bug reports (no network names or addresses)"
		say "  7  Turn amtm updates $( [ "$AMTM_UPDATE" = on ] && printf off || printf on)"
		say "  8  Development version from GitHub, for testing unreleased changes"
		say "  9  Uninstall"
		say "  e  Exit"
		printf '\n Choose an option: '
		read -r opt || { say ""; return 0; }
		say ""
		case "$opt" in
			1) ( status ); menu_pause ;;
			2) ( scan ); menu_pause ;;
			3) menu_collection ;;
			4|5|8)
				before=$(md5sum < "$SCRIPT" 2>/dev/null)
				if [ "$opt" = 8 ]; then
					say " Development versions are unreleased and can be broken. Option 4 goes back to the latest release."
					printf ' Branch (Enter for main, e to go back): '; read -r br || br=e
					case "$br" in e|E) continue ;; esac
					( update_dev "${br:-main}" )
				elif [ "$opt" = 5 ]; then ( update force ); else ( update ); fi
				menu_pause
				# the update replaced this script: carry on in the new one
				[ -f "$SCRIPT" ] && [ "$(md5sum < "$SCRIPT" 2>/dev/null)" != "$before" ] && exec sh "$SCRIPT" menu ;;
			6) ( debug ); menu_pause ;;
			7)
				if [ "$AMTM_UPDATE" = on ]; then AMTM_UPDATE=off; else AMTM_UPDATE=on; fi
				write_conf; log "amtm updates turned $AMTM_UPDATE" ;;
			9) menu_uninstall && return 0 ;;
			e|E|q|Q) return 0 ;;
			'') ;;
			*) say " $opt isn't an option."; menu_pause ;;
		esac
	done
}

# Run from a copy of another version than the one installed (an old /tmp/wifiinsight.sh from an earlier
# install, say): hand over to the installed script, so old code doesn't run against the current data.
case "${1:-menu}" in
	install|update|uninstall|check|version) ;;
	*)	if [ "$0" != "$SCRIPT" ] && [ -f "$SCRIPT" ]; then
			iv=$(sed -n 's/^VERSION="\([0-9][0-9.]*\)".*/\1/p' "$SCRIPT" | head -1)
			if [ -n "$iv" ] && [ "$iv" != "$VERSION" ]; then
				say "This is WiFi Insight $VERSION at $0, but $iv is installed: running that instead."
				exec sh "$SCRIPT" "$@"
			fi
		fi ;;
esac

case "$1" in
	'')            if [ -t 0 ] && [ -t 1 ]; then menu; else usage; fi ;;
	menu)          menu ;;
	install)       install ;;
	update)        if [ "$2" = dev ]; then update_dev "$3"; else update "$2"; fi; exit $? ;;
	check)         check_support; exit $? ;;
	uninstall)     uninstall "$2" ;;
	startup)       startup ;;
	collect)       collect "$2" ;;
	scan)          scan "$2" ;;
	export)        lowprio; ready && export_all ;;
	prune)         prune ;;
	status)        status ;;
	repair)        repair "$2" ;;
	trickle)       trickle ;;
	debug)         debug ;;
	service_event) service_event "$2" "$3" ;;
	version)       say "$VERSION" ;;
	collection)    if [ -n "$2" ]; then set_collection "$2"; else say "Collection: $(collection_text)"; fi ;;
	amtmupdate)    amtm_update "$2"; exit $? ;;
	*)             usage ;;
esac
