#!/bin/sh
###############################################################################
#  WiFi Insight for Asuswrt-Merlin
#  Channel interference history, channel-change events and a spectrum
#  heatmap for Broadcom-based Merlin routers (built on an RT-AX86U).
#
#  Pages: Insight, Site Survey, Channel Statistics, Troubleshooting, Settings
#
#  Usage: wifiinsight.sh install | update [force] | uninstall [--keep-data] |
#                        status | startup | collect | scan | export | prune | debug
#
#  Install:  curl -fsL --retry 3 https://github.com/IfSugar/wifiinsight/releases/latest/download/wifiinsight.sh \
#              -o /tmp/wifiinsight.sh && sh /tmp/wifiinsight.sh install
###############################################################################

VERSION="1.0.11"
NAME="wifiinsight"
TITLE="WiFi Insight"

# WI_ROOT lets the script be tested off-router; it is empty on the router.
ROOT="${WI_ROOT:-}"
ADDON_DIR="$ROOT/jffs/addons/$NAME"
SCRIPT="$ADDON_DIR/$NAME.sh"
PAGE_SRC="$ADDON_DIR/$NAME.asp"
CONF="$ADDON_DIR/config"
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
DATA_DIR="/opt/var/lib/$NAME"
SQLITE="/opt/bin/sqlite3"
[ -f "$CONF" ] && . "$CONF"
DB="$DATA_DIR/$NAME.db"

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

sql() { "$SQLITE" -batch -noheader -cmd ".timeout 8000" "$DB" "$@"; }

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

band_of_hex() {
	h=$(( $1 ))
	case $(( h & 0xc000 )) in
		0) echo 2g ;; 49152) echo 5g ;; 32768) echo 6g ;; *) echo 5g ;;
	esac
}

width_of_hex() {
	case $(( ($1 & 0x3800) >> 11 )) in
		2) echo 20 ;; 3) echo 40 ;; 4) echo 80 ;; 5|6) echo 160 ;; 7) echo 320 ;; *) echo 20 ;;
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
			for g in 1 2 3; do [ "$(nvram get wl${r}.${g}_bss_enabled)" = "1" ] && nvram get wl${r}.${g}_ssid; done
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
		if (match($0, /Channel: [0-9]+(\/[0-9]+)?/)) chf = substr($0, RSTART + 9, RLENGTH - 9)
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

# The web page follows a scan through scanstate.htm: state running|done|error, a sequence number
# that goes up by one per scan, and each radio's result (ok, busy, empty, off).
scan_state() {   # state [bands-json] [message]
	wd=$(web_dir); mkdir -p "$wd"
	printf '{"state":"%s","seq":%s,"ts":%s,"bands":{%s},"msg":"%s"}\n' "$1" "${SCAN_SEQ:-0}" "$(now)" "$2" "$(js "$3")" \
		| write_atomic "$wd/scanstate.htm"
}
scan_next_seq() {
	mkdir -p "$TMPD"
	SCAN_SEQ=$(( $(cat "$TMPD/scan_seq" 2>/dev/null || echo 0) + 1 )); echo "$SCAN_SEQ" > "$TMPD/scan_seq"
}

scan() {
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
	ownf=$(own_ssids_file); bands=""
	for r in $(radios); do
		ifc=$(nvram get wl${r}_ifname)
		hex=$(wl -i "$ifc" chanspec 2>/dev/null | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p')
		[ -n "$hex" ] || continue
		band=$(band_of_hex "$hex"); result=ok
		if [ "$(wl -i "$ifc" isup 2>/dev/null)" != "1" ]; then
			result=off
		else
			# the radio refuses a scan while it's already scanning (Smart Connect, AiMesh): retry briefly
			started=0
			for try in 1 2 3; do wl -i "$ifc" scan >/dev/null 2>&1 && { started=1; break; }; sleep 2; done
			if [ $started -eq 0 ]; then
				result=busy
			else
				sleep 6
				res="$TMPD/scan_$band.txt"
				wl -i "$ifc" scanresults > "$res" 2>/dev/null
				if ! grep -q '^BSSID' "$res"; then sleep 3; wl -i "$ifc" scanresults > "$res" 2>/dev/null; fi
				if grep -q '^BSSID' "$res"; then
					parse_scan "$(now)" "$band" "$(radio_channels "$ifc" "$band")" "$ownf" < "$res" | sql
				else
					result=empty
				fi
			fi
		fi
		bands="$bands${bands:+,}\"$band\":\"$result\""
		log "scan $band ($ifc): $result"
	done
	rm -f "$SCAN_FLAG"
	export_scans
	scan_state done "$bands"
	flock -u 7
	log "scan complete"
}

# A scan pauses sampling; a flag left behind by a killed scan is ignored after 5 minutes.
scanning() {
	[ -f "$SCAN_FLAG" ] || return 1
	ft=$(date -r "$SCAN_FLAG" +%s 2>/dev/null) || return 1
	[ $(( $(now) - ft )) -lt 300 ]
}

# ---- export (JSON files read by the web page) -------------------------------
# httpd runs .htm/.js files through its <% %> / <# #> template engine, so no '<' may reach
# the page raw. In this JSON '<' can only occur inside strings (SSIDs), where < is identical.
write_atomic() {   # file content-from-stdin
	tmp="$1.$$.tmp"
	if sed 's/</\\u003c/g' > "$tmp"; then mv -f "$tmp" "$1"; else rm -f "$tmp"; return 1; fi
}

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
	{
		printf '{"version":"%s","generated":%s,"sample_interval":%s,"scan_interval":%s,"retain_days":%s,' \
			"$VERSION" "$t" "$SAMPLE_INTERVAL" "$SCAN_INTERVAL" "$RETAIN_DAYS"
		printf '"data_dir":"%s","db_bytes":%s,"own_ssids":[%s],"extra_own":"%s",' \
			"$(js "$DATA_DIR")" "$(jnum "$dbb")" "$ownj" "$(js "$EXTRA_OWN_SSIDS")"
		printf '"radios":%s,"samples":' "$(radios_json)"
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
		json_out '{}' "SELECT json_group_object(band, json(a)) FROM (SELECT band, json_group_array(json_array(b, ch, sc, ap, be, ow, n)) AS a FROM (SELECT band, ((ts+$off)/21600)*21600-$off AS b, ch, round(avg(score),1) AS sc, max(aps) AS ap, max(best) AS be, round(avg(own),1) AS ow, count(*) AS n FROM scans WHERE ts>=$since GROUP BY band, b, ch ORDER BY band, b, ch) GROUP BY band);"
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
		json_out '{}' "SELECT json_group_object(band, json(a)) FROM (SELECT band, json_group_array(json_array(ts,ch,score,aps,best,own)) AS a FROM (SELECT * FROM scans WHERE ts>=$since ORDER BY band, ts, ch) GROUP BY band);"
		printf ',"aps":'
		json_out '{}' "SELECT json_group_object(band, json(a)) FROM (SELECT x.band, json_group_array(json_object('ssid',x.ssid,'bssid',x.bssid,'rssi',x.rssi,'ctl',x.ctl,'center',x.center,'width',x.width,'util',x.util,'own',x.own,'phy',x.phy,'sec',x.sec,'snr',x.snr)) AS a FROM (SELECT p.* FROM aps p JOIN (SELECT band, max(ts) AS mt FROM aps GROUP BY band) l ON p.band=l.band AND p.ts=l.mt ORDER BY p.band, p.rssi DESC) x GROUP BY x.band);"
		printf '}\n'
	} | write_atomic "$wd/scans.htm"
}

export_all() { export_live; export_week; export_month; export_scans; }

# ---- scheduled entry points --------------------------------------------------
collect() {
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
	sql "DELETE FROM samples WHERE ts<$cut; DELETE FROM scans WHERE ts<$cut; DELETE FROM aps WHERE ts<$cut; DELETE FROM events WHERE ts<$evcut; PRAGMA optimize;"
	[ "$(date +%w)" = "0" ] && sql "VACUUM;"
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

cron_add() {
	cru a "${NAME}_collect" "* * * * * $SCRIPT collect"
	if [ "$SCAN_INTERVAL" -gt 0 ] 2>/dev/null; then
		if [ "$SCAN_INTERVAL" -ge 60 ]; then
			cru a "${NAME}_scan" "7 */$((SCAN_INTERVAL / 60)) * * * $SCRIPT scan --delay"
		else
			cru a "${NAME}_scan" "*/$SCAN_INTERVAL * * * * $SCRIPT scan --delay"
		fi
	else
		cru d "${NAME}_scan" 2>/dev/null
	fi
	cru a "${NAME}_prune" "23 4 * * * $SCRIPT prune"
}

cron_del() {
	for j in collect scan prune; do cru d "${NAME}_$j" 2>/dev/null; done
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
	write_conf
	cron_add
	ready && export_all
	log "settings updated: sample=$SAMPLE_INTERVAL scan=$SCAN_INTERVAL retain=$RETAIN_DAYS"
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
	} END { print t }' /proc/mounts 2>/dev/null
}

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
			hex=$(wl -i "$ifc" chanspec 2>/dev/null | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p')
			case "$([ -n "$hex" ] && band_of_hex "$hex")" in 2g) b="2.4 GHz" ;; 5g) b="5 GHz" ;; 6g) b="6 GHz" ;; *) b="radio $r" ;; esac
			bands="$bands|$b"
			if [ "$(wl -i "$ifc" isup 2>/dev/null)" != "1" ]; then
				ck_warn "$b ($ifc) is switched off. It will be monitored once it's on."
				off=$((off + 1)); continue
			fi
			hdr=$(wl -i "$ifc" chanim_stats 2>/dev/null | grep -E '^(chanspec|chspec)[[:space:]]' | head -1)
			missing=""
			for col in tx inbss obss nocat idle; do
				case " $(printf '%s' "$hdr" | tr -s ' \t' '  ') " in *" $col "*) ;; *) missing="$missing $col" ;; esac
			done
			if [ -z "$hdr" ]; then ck_warn "$b ($ifc) doesn't report airtime statistics (wl chanim_stats)."
			elif [ -n "$missing" ]; then ck_warn "$b ($ifc) airtime statistics lack:$missing"
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
			fi ;;
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
	[ -f "$CONF" ] || write_conf
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
		say "Running the first neighbour scan (Wi-Fi may hiccup for a second)..."
		scan
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
	if [ "$new" = "$VERSION" ] && [ "$1" != "force" ]; then
		rm -rf "$dl"; say "Already up to date ($VERSION)."; return 0
	fi
	if ver_gt "$VERSION" "$new" && [ "$1" != "force" ]; then
		rm -rf "$dl"; say "This is $VERSION, newer than the latest release ($new). Nothing was changed; 'update force' installs $new."; return 0
	fi
	if ! fetch "$rel/$NAME.asp" "$dl/$NAME.asp" || ! grep -q "wifiinsight-version: $new " "$dl/$NAME.asp"; then
		rm -rf "$dl"; die "Couldn't download the matching web page; nothing was changed."
	fi
	say "Updating $VERSION -> $new (settings and history are kept)"
	sh "$dl/$NAME.sh" install; rc=$?
	rm -rf "$dl"
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
		case "$DATA_DIR" in */$NAME) rm -rf "$DATA_DIR" ;; *) rm -f "$DB"; say "Left $DATA_DIR in place (deleted only the database)." ;; esac
	fi
	rm -rf "$ADDON_DIR"
	say "Removed."
}

status() {
	say "$TITLE $VERSION"
	say "Data:        $DB ($( [ -f "$DB" ] && du -h "$DB" | cut -f1 || echo missing))"
	say "Web page:    $(cat "$ADDON_DIR/webui_page" 2>/dev/null || echo 'not mounted')"
	say "Ready:       $(ready && echo yes || echo 'no (NTP or storage)')"
	say "Cron:";  cru l 2>/dev/null | grep "$NAME" | sed 's/^/  /'
	if [ -f "$DB" ]; then
		t=$(now)
		sql "SELECT '  ' || band || ': ' || count(*) || ' samples, last ' || ($t - max(ts)) || 's ago' FROM samples GROUP BY band;"
		sql "SELECT '  last scan: ' || ($t - max(ts)) || 's ago' FROM scans;"
		say "Recent events:"
		sql "SELECT '  ' || datetime(ts,'unixepoch','localtime') || '  ' || band || '  ' || tag || '  ' || coalesce(old,'') || ' -> ' || coalesce(new,'') FROM events ORDER BY ts DESC LIMIT 8;"
	fi
}

fw_version() {   # e.g. 3004.388.12_2
	fw=$(nvram get buildno); ext=$(nvram get extendno); fv=$(nvram get firmver | tr -d .)
	[ -n "$ext" ] && fw="${fw}_$ext"; [ -n "$fv" ] && fw="$fv.$fw"
	echo "$fw"
}

# Everything a bug report or router report needs, and nothing personal: no network names, no MAC
# addresses, no IP addresses. Works without installing (sh /tmp/wifiinsight.sh debug).
debug() {
	say "$TITLE $VERSION"
	say "Router:      $(nvram get productid) $(nvram get odmpid)  firmware $(fw_version)  $(uname -m)"
	say "BusyBox:     $(busybox 2>/dev/null | head -1 | cut -d' ' -f2)   sqlite3: $("$SQLITE" --version 2>/dev/null | cut -d' ' -f1)"
	say "Smart Connect: $(nvram get smart_connect_x)   wl_ifnames: $(nvram get wl_ifnames)"
	say "acsd: $(pidof acsd2 acsd || echo 'not running')"
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

case "$1" in
	install)       install ;;
	update)        update "$2"; exit $? ;;
	check)         check_support; exit $? ;;
	uninstall)     uninstall "$2" ;;
	startup)       startup ;;
	collect)       collect "$2" ;;
	scan)          scan "$2" ;;
	export)        lowprio; ready && export_all ;;
	prune)         prune ;;
	status)        status ;;
	debug)         debug ;;
	service_event) service_event "$2" "$3" ;;
	version)       say "$VERSION" ;;
	*) say "Usage: $0 install | check | update [force] | uninstall [--keep-data] | status | scan | export | debug | version" ;;
esac
