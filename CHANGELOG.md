# Changelog

What changed in each release of WiFi Insight. The release workflow copies a version's section into its GitHub release notes, so write for people running the addon.

## 1.2.0

- **Measured spectrum.** During every neighbour scan the radio also measures each channel it visits: the share of airtime used by other networks, non-Wi-Fi energy (microwaves, baby monitors, Bluetooth…) and energy it couldn't decode, plus the noise floor. WiFi Insight now saves those figures after each scan and, where the router reports them, the Spectrum heatmap and *Load per channel* show them instead of an estimate built from the networks heard. Tick *Others Wi-Fi*, *Non-Wi-Fi* and *Unclassified* to choose what counts, or switch to *Estimated* to see the old view. The quietest-channel suggestions use the same figures, and Channel Statistics adds a **noise floor for every channel**. It needs no extra scans and adds no Wi-Fi hiccups. The figures start with the first neighbour scan after updating (press *Scan now* to start sooner); until then the page says so. Routers whose driver doesn't report per-channel figures keep the estimate, as before. Tested on an RT-AX86U (3004.388); routers on 3006.102 print these figures differently, so they may keep the estimate until a sample of their output comes in.
- **Weather-radar channels marked.** Channels 120, 124 and 128 (5600–5650 MHz) share the band with weather radars. In Europe, the US and Canada, Quietest options, the Spectrum and Signal map axes, the tooltips and the Networks table now mark them (and wider blocks that include them) as *DFS · weather radar*, with a note on what that means there: in Europe the router must listen for radar for 10 minutes before using them instead of 1; in the US they're shared with airport weather radars (TDWR); in Canada they've been allowed only since 2025. The region comes from the radio's country code. `debug` prints it.
- `scan` and the syslog say how many channels were measured, and "1 networks" now reads "1 network".
- **A menu for the terminal, ready for amtm.** Run `/jffs/addons/wifiinsight/wifiinsight.sh` with no arguments for a menu: status, scan now, collection (on, scans paused or off), update, reinstall, debug report, amtm updates on or off, and uninstall (it asks first). amtm opens the same menu.
- **amtm can update WiFi Insight** (`amtmupdate`), along with your other scripts, from its update option. It installs the latest release, prints two lines and logs the details to `/tmp/wifiinsight/amtmupdate.log`. To keep amtm from updating it, choose *Turn amtm updates off* in the menu (or set `AMTM_UPDATE=off` in the config); `update` still works.
- **Try unreleased changes:** `wifiinsight.sh update dev` installs the newest code on `main` (or `update dev <branch>` for another branch, such as a fix waiting for release), keeping your settings and history. `status`, `debug` and the page's footer say when a development version is installed. `update` and amtm still only install releases, and bring a development version back to the latest release. Menu option 8 does the same.
- New command: `wifiinsight.sh collection on|paused|off`, the same as Settings → Collection on the page.
- Updating no longer runs an extra neighbour scan when you already have history, so `update` finishes sooner and doesn't make Wi-Fi hiccup.

## 1.1.1

- **Fixed: routers with a 6 GHz radio were refused** with "This router has two 5 GHz radios" (GT-AXE11000, RT-BE92U, RT-BE96U, GT-BE19000AI). WiFi Insight read the 6 GHz band code as 5 GHz. It now reads all three bands correctly, and 320 MHz channels on 6 GHz too. Thanks to BobWadd for the RT-BE96U report!
- 6 GHz on the page: Channel Statistics suggests the quietest 40, 80, 160 and 320 MHz blocks, and its channel axis labels every few channels so the 59 channels stay readable.
- Routers with two radios on the same band (GT-AX11000, ZenWiFi Pro XT12) are still refused for now, as before.

## 1.1.0

- **Quiet hours.** Settings → Quiet hours: mark the half hours of the week when the router shouldn't run its scheduled neighbour scans, so there's no Wi-Fi hiccup while you're gaming, streaming or on a call. Click or drag on the week grid, or start from a preset (evenings, work hours, weekends). Sampling carries on, since it doesn't touch Wi-Fi, and Scan now still works. Times are the router's local time. Thanks to jksmurf for the idea!
- **Collection: On, Scans paused or Off.** *Scans paused* keeps sampling but runs no scheduled scans until you switch back. *Off* stops sampling and scanning without uninstalling: the page, settings and history stay as they are.
- Insight shows when it's quiet ("Quiet until 20:00" next to Scan now, a note at the top and a marked row on the spectrum), and when scans are paused or collection is off.
- **5 GHz scans on routers with Merlin 3006.102** (GT-AX6000, RT-BE88U and other Wi-Fi 7 models): the Spectrum, Site Survey and Channel Statistics stayed empty on 5 GHz while 2.4 GHz worked. WiFi Insight gave each scan 9 seconds, and a 5 GHz scan on these drivers can take longer. It now waits for the driver to finish: up to 20 seconds on 2.4 GHz and 45 seconds on 5 and 6 GHz, and up to 20 seconds more when the radio is busy with another scan. Thanks to ColDen and AvalonOC for the reports!
- When a band's scan fails, Scan now says why, quoting the driver (for example: 5 GHz: no results, wl said "Not Ready" for 45 s), and so do the syslog and `wifiinsight.sh scan`, which now prints each band's result.
- `status` and `debug` show the collection mode and the quiet hours, and `status` says when it's quiet now.
- The config file has two new settings, `COLLECTION` and `QUIET`, added with their defaults when you update. See the README.

## 1.0.11

- **Routers on Merlin 3006.102** (the GT-AX6000, RT-AX86U Pro, RT-AX88U Pro and the Wi-Fi 7 models): their newer driver prints airtime statistics in a newer layout (`version: 4`, channels such as `100/80` instead of hex codes, an extra `busy` column, and on Wi-Fi 7 models a `chspec` header). On the RT-BE88U the router check refused it ("No radio provides the airtime statistics"); on the GT-AX6000 the check passed, but no samples were recorded, so the charts stayed empty. WiFi Insight now reads every layout. Thanks to the RT-BE88U and GT-AX6000 owners who sent their output!
- The router check now reads a row of airtime statistics exactly as sampling does, so a layout WiFi Insight can't read is reported at install instead of showing up as empty charts. When the driver answers with an error, the check quotes it.
- `update` and the install command now get the **latest release** instead of the newest code on GitHub, so unreleased changes never reach your router. `update` also won't replace a newer version with an older release unless you use `update force`.
- The install command in the README now downloads from the latest release: `https://github.com/IfSugar/wifiinsight/releases/latest/download/wifiinsight.sh`.

## 1.0.10

- `wifiinsight.sh debug` is now a complete report for bug reports and router reports. It starts with the WiFi Insight version, router model, firmware, BusyBox and sqlite3 versions and Smart Connect, and covers every radio, including a fourth one, with its band type and driver version. It still prints no network names, MAC addresses or IP addresses, and works without installing (`sh /tmp/wifiinsight.sh debug`).
- New issue forms for bug reports, install or setup problems, router reports and feature requests, plus a security policy for reporting problems privately.

## 1.0.9

- **Fixed: charts went empty after about 9 hours of history.** The Insight and Troubleshooting charts and the tiles showed "No samples in this range yet", and `update` printed `[: Argument list too long`. On Merlin, the shell can hand at most 128 KB to some of the commands the script uses, and a day of samples is about 350 KB, so the data was dropped from the file the page reads. The script now writes the data files without going through that limit. Your history was never lost: once you update, the charts fill straight away.
- Fixed the same limit for the Spectrum heatmap, which would have gone empty after about three days of scans, and for radar events in a very long syslog, which were no longer picked up.
- The router check showed a negative number of MB free for a USB drive with more than 2 TB free, because Merlin's shell arithmetic is 32-bit. The check itself was right; only the number was wrong.
- Releases are now tested on a shell set up like Merlin's, with only the BusyBox commands Merlin includes, using a full day of samples, a week of scans and a long radar log. A command Merlin lacks, or data that's too big for it, now fails the release instead of breaking on routers.

## 1.0.8

- The addon no longer keeps `user1.asp` free. It takes the first free addon page slot, skips slots other addons already use, and keeps its slot across reboots and updates. The `RESERVED_PAGES` setting is gone; an old line for it in your config is ignored.
- The router check now refuses routers with two radios on the same band, such as 5 GHz-1 and 5 GHz-2 on a GT-AX11000, and routers with four radios. WiFi Insight keeps history per band, so those radios would overwrite each other's data. Support for them is planned. Dual-band routers and 2.4 + 5 + 6 GHz tri-band routers pass as before.

## 1.0.7

- **Longer ranges are readable.** 12H, 1D and 7D used to plot every 30-second sample, thousands of points, which looked like noise. They now show averages: 5 minutes for 12H, 10 minutes for 1D and an hour for 7D, about 150 points per chart. Tooltips say which average you're looking at. 10M and 1H still show every sample.
- **New 30D range**, in 4-hour averages. The router keeps an hourly summary of the last 30 days for it, refreshed once an hour.
- **Spectrum heatmap on 7D and 30D:** rows are grouped into 3-hour (7D) or daily (30D) averages instead of one hairline row per scan, and channel load averages use the same data.
- On 7D and 30D, the charts leave out the daily scheduled-reboot markers so the lines stay readable. They're still listed under Channel events.
- Averages follow your local time, so daily rows start at midnight and hourly points sit on the hour.
- Settings: each dropdown is sized to its text again (1.0.6 made them all one width). The even padding and the new arrow stay.
- Troubleshooting → Airtime breakdown: click any name in the legend to show or hide it, like the other charts. Hide everything but *Your TX* to see just your transmit time. The chart rescales to what's shown.
- Airtime breakdown adds up to exactly 100%. The radio measures and rounds each share separately, so they used to total roughly 97–105% and the top edge wobbled. Each sample is now scaled to 100%, and the raw counters table below is unchanged.

## 1.0.6

- Settings: the dropdowns have even padding on both sides and a matching arrow, are all the same width, and line up with the text field below them.

## 1.0.5

- `update` retries each download up to three times, so a momentary failure no longer stops the update. Before, you sometimes had to run `update` again.
- If a file still can't be saved, the message now says how much free space the router's `/tmp` has, to show what went wrong.
- Each update run uses its own temporary folder.

## 1.0.4

- **Fixed: Scan now didn't scan.** The button showed "Scanning…" for about a minute and then gave up, because the request went to a page address that doesn't exist on 388 firmware. It now scans both radios in about 15 seconds.
- **Fixed: Settings → Save didn't save**, for the same reason. If you changed settings before 1.0.4, save them again.
- Scan now shows its progress and the outcome: "Scan complete", which radio was busy or heard nothing, or that the router didn't start the scan.
- If a radio is already scanning (Smart Connect and AiMesh do this), the scan retries for a few seconds instead of skipping that radio.

## 1.0.3

The first tagged release. It includes everything from 1.0.0 to 1.0.2.

- **Spectrum colours:** white means a clean channel, and deeper blue means a busier one. The channel load chart uses the same scale.
- **Fixed: the page didn't work on real firmware.** The router's own menu and the dashboard failed to draw, and the charts couldn't load next to the firmware's scripts. Tested against the 3004.388.12_2 web UI.
- **The tab now appears under Wireless**, right after *Professional*. If you don't see it, reload the page with Ctrl+F5 or Cmd+Shift+R.
- **Fixed: `update` could fail** with "No such file or directory". It now downloads the script and page from the newest commit, so you always get a matching pair, and it explains any failed download.
- **The installer checks the router before changing anything:** firmware, Broadcom driver, BusyBox features, Entware and `sqlite3`, USB storage, JFFS space and a free page slot. If anything is missing, nothing is installed.
- Background jobs run at the lowest CPU priority, and the menu is only edited when the result is exactly the line expected.
