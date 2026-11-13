#!/bin/bash
# Regression test: each radio's band, width and centre are read correctly from its chanspec, and the
# router check accepts every radio layout, naming radios as the router does.
#
# Up to 1.1.0 the 6 GHz band bits (0x4000) were read as 5 GHz, so an RT-BE96U was refused with
# "This router has two 5 GHz radios". Up to 1.3.0, routers with two radios on one band, or four radios,
# were refused, and 320 MHz was read as 160 around the wrong centre. Chanspecs here are real ones from
# routers in the forum thread (RT-AX86U, GT-AX6000, RT-BE88U, RT-BE96U), plus 6 GHz 160 MHz and the Wi-Fi 7
# driver's 320 MHz ones built from its bcmwifi_channels.h (impl103/impl105 in the Merlin source): width
# bits 0x3000, bits 0-5 the centre in 160 MHz steps from channel 31, bits 6-10 the primary's place.
#
# Usage: .github/tests/radio-bands.sh [path/to/wifiinsight.sh]   (needs busybox)
set -eu
script=${1:-$(cd "$(dirname "$0")/../.." && pwd)/wifiinsight.sh}
case "$script" in /*) ;; *) script=$PWD/$script ;; esac
bb=$(command -v busybox) || { echo "::error::radio-bands.sh needs busybox installed"; exit 1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

# ---- 1: decoding, with BusyBox ash like on the router ----------------------------------------
sed -n '/^band_of_hex() {/,/^}/p; /^width_of_hex() {/,/^}/p; /^center_of_hex() {/,/^}/p; /^ctl_of_cs() {/,/^}/p' "$script" > "$t/cs.sh"
decode() { "$bb" ash -c '. "$1"; printf "%s %s %s %s" "$(band_of_hex "$3")" "$(width_of_hex "$3")" "$(ctl_of_cs "$2")" "$(center_of_hex "$3")"' sh "$t/cs.sh" "$1" "$2"; }
while read -r cs hex want; do
	got=$(decode "$cs" "$hex")
	if [ "$got" = "$want" ]; then ok "decode $cs ($hex): $got"
	else bad "decode $cs ($hex): got '$got', want '$want'"; fi
done <<'EOF'
6 0x1006 2g 20 6 6
11u 0x1909 2g 40 11 9
1 0x1001 2g 20 1 1
100l 0xd866 5g 40 100 102
100/80 0xe06a 5g 80 100 106
36/160 0xe832 5g 160 36 50
149/80 0xe09b 5g 80 149 155
100/160 0xe872 5g 160 100 114
6g1/80 0x6007 6g 80 1 7
6g37/160 0x692f 6g 160 37 47
6g1/320-1 0x7000 6g 320 1 31
6g37/320-1 0x7240 6g 320 37 31
6g65/320-2 0x7201 6g 320 65 63
6g133/320-1 0x7044 6g 320 133 159
EOF

# ---- 2: the router check, on stand-ins for real radio layouts ------------------------------------
# Only the radio lines matter here; the rest of the check (storage, sqlite...) is ignored.
mkdir -p "$t/bin" "$t/root/www/user" "$t/root/usr/sbin" "$t/root/jffs/addons" "$t/root/tmp"
HDR='chspec tx inbss obss nocat nopkt doze txop goodtx badtx glitch badplcp knoise idle busy timestamps'
cat > "$t/bin/wl" <<EOF
#!/bin/sh
f="$t/radios"; ifc=\$2; cmd=\$3
line=\$(grep "^\$ifc " "\$f") || { echo "wl: wl driver adapter not found" >&2; exit 1; }
set -- \$line
case "\$cmd" in
	isup) echo 1 ;;
	chanspec) echo "\$2 (\$3)" ;;
	chanim_stats) printf 'version: 4\n%s\n%s 1 0 4 1 1 0 96 0 0 1 0 -92 97 4 152946414\n' "$HDR" "\$2" ;;
	*) exit 1 ;;
esac
EOF
cat > "$t/bin/nvram" <<EOF
#!/bin/sh
case "\$2" in
	wl[0-3]_ifname) n=\${2%_ifname}; awk -v n="\$n" '\$4 == n { print \$1 }' "$t/radios" ;;
esac
EOF
chmod +x "$t/bin/wl" "$t/bin/nvram"
check() { WI_ROOT="$t/root" PATH="$t/bin:$PATH" "$bb" ash "$script" check 2>&1 | grep -E 'GHz|radio|radios' || true; }
layout() {   # name, then lines: ifc chanspec hex wlN
	name=$1; shift; printf '%s\n' "$@" > "$t/radios"; out=$(check)
}
expect_line()   { if printf '%s\n' "$out" | grep -qF -- "$1"; then ok "$name: $1"; else bad "$name: missing '$1'"; printf '%s\n' "$out" | sed 's/^/      | /'; fi; }
expect_no_line() { if printf '%s\n' "$out" | grep -qF -- "$1"; then bad "$name: unexpected '$1'"; printf '%s\n' "$out" | sed 's/^/      | /'; else ok "$name: no '$1'"; fi; }

layout "RT-BE96U (2.4 + 5 + 6 GHz)" "wl0 5 0x1005 wl0" "wl1 149/80 0xe09b wl1" "wl2 6g1/80 0x6007 wl2"
expect_line "[ OK ] 2.4 GHz (wl0) airtime statistics"
expect_line "[ OK ] 5 GHz (wl1) airtime statistics"
expect_line "[ OK ] 6 GHz (wl2) airtime statistics"
expect_no_line "This router has two"

layout "6 GHz at 320 MHz" "wl0 5 0x1005 wl0" "wl1 149/80 0xe09b wl1" "wl2 6g1/320-1 0x7000 wl2"
expect_line "[ OK ] 6 GHz (wl2) airtime statistics"
expect_no_line "This router has two"

layout "GT-AX11000 (2.4 + 5 + 5 GHz)" "eth6 6 0x1006 wl0" "eth7 36/80 0xe02a wl1" "eth8 149/80 0xe09b wl2"
expect_line "[ OK ] 5 GHz-1 (eth7) airtime statistics"
expect_line "[ OK ] 5 GHz-2 (eth8) airtime statistics"
expect_no_line "This router has"

layout "GT-AXE16000 (5 + 5 + 6 + 2.4 GHz)" "eth7 36/80 0xe02a wl0" "eth8 100/80 0xe06a wl1" "eth9 6g37/160 0x692f wl2" "eth10 6 0x1006 wl3"
expect_line "[ OK ] 5 GHz-1 (eth7) airtime statistics"
expect_line "[ OK ] 5 GHz-2 (eth8) airtime statistics"
expect_line "[ OK ] 6 GHz (eth9) airtime statistics"
expect_line "[ OK ] 2.4 GHz (eth10) airtime statistics"
expect_no_line "This router has"

layout "GT-BE98 Pro (5 + 6 + 6 + 2.4 GHz)" "wl0 36/160 0xe832 wl0" "wl1 6g37/320-1 0x7240 wl1" "wl2 6g133/320-1 0x7044 wl2" "wl3 11 0x100b wl3"
expect_line "[ OK ] 5 GHz (wl0) airtime statistics"
expect_line "[ OK ] 6 GHz-1 (wl1) airtime statistics"
expect_line "[ OK ] 6 GHz-2 (wl2) airtime statistics"
expect_line "[ OK ] 2.4 GHz (wl3) airtime statistics"

layout "RT-BE88U (2.4 + 5 GHz)" "wl0 6 0x1006 wl0" "wl1 36/160 0xe832 wl1"
expect_line "[ OK ] 2.4 GHz (wl0) airtime statistics"
expect_line "[ OK ] 5 GHz (wl1) airtime statistics"
expect_no_line "This router has two"

[ $fail -eq 0 ] && echo "Radio bands: all checks passed." || { echo "::error::Radio bands: some checks failed."; exit 1; }
