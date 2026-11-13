# Changelog

What changed in each release of WiFi Insight. The release workflow copies a version's section into its GitHub release notes, so write for people running the addon.

## 1.3.1

- **An old copy hands over to the installed script.** The install command downloads the script to `/tmp/wifiinsight.sh`, and that copy stayed there until a reboot: running it later (`sh /tmp/wifiinsight.sh scan`, say) ran the old version's code, which made a 1.3.0 router look like 1.2.0. Now `install` removes that copy when it's done, and a copy whose version differs from the installed one says so and runs the installed script instead (except for `install`, `update`, `uninstall`, `check` and `version`).
- **When your router refuses 5 GHz scans on a DFS channel, the page says what avoids it.** Some routers refuse full 5 GHz scans while on a DFS channel; many don't (an RT-AX86U in Europe scans them fine). Only when your router's scans were refused, or had to go one channel at a time, while it's on a DFS channel, the Spectrum, Site Survey and Channel Statistics now add that a channel outside 52–144 avoids it (in Wireless → General, un-tick "Enable 160 MHz" and "Auto select channel including DFS channels"), and what that costs. Thanks to SashaSolitaire for finding it!
- **Hidden networks from your own devices count as yours.** An AiMesh node's hidden backhaul or a Wi-Fi 7 router's extra links have no name, so they counted as neighbours and as interference. A hidden network whose address matches one of your named networks' in all but the first byte and the last 4 bits, which only the same device shares, now counts as yours.
- **A warning when the history drive has no journal.** On ext2, FAT, exFAT, NTFS, or ext4 made without a journal (amtm offers that), a power cut while the drive is writing can damage the database, as happened on a GT-AX6000. `check`, `status`, `debug` and the Settings tab now name the drive's filesystem and say so, and the damaged-database warning mentions it. ext3/ext4 with a journal are fine.
- *Scan now* also refreshes the channel tile, which could show the old channel for up to a minute after a channel change.

## 1.3.0

- **Scans that cover only part of the band are stored as such.** A scan taken one channel at a time, or one the driver stopped early, used to be saved as if every channel had been scanned, so the channels it missed showed up as empty and quiet, and *Quietest options* could suggest them. Now only the channels a scan covered are stored. Where the latest scans didn't cover a channel, *Load per channel* and *Quietest options* use the newest scan within the previous 6 hours that did, and Site Survey and *Networks per channel* keep the networks it heard there. The page says when it does.
- **One channel at a time, without skipping channels.** On routers that take a single-channel scan only every so often, WiFi Insight now waits on each channel until the driver takes it, instead of moving on after 20 seconds, so no channel is left out. It stops when nothing has been taken for a minute, or after 150 seconds, and the next scan carries on from there. Once the driver has refused a full scan on a channel, WiFi Insight tries a full scan just once on later scans there, not for 20 seconds, and gives it the full 20 seconds again every 6 hours. Sampling carries on during one-channel scans.
- **Quiet channels count as scanned.** A channel can give exactly the same figures twice when nothing is on it, which looked like a channel the scan never reached: its figures weren't stored, and at the end of the band it set off a needless second scan. Now a channel where the scan heard a network counts as reached too.
- **`repair` runs the full check.** It used SQLite's quick check, which doesn't compare indexes with their tables, so some damage passed as fine. It now runs the full integrity check (a minute or so on a large database).
- **Safer weekly compaction.** The weekly VACUUM rewrites the whole database, the riskiest write if the power goes. It now runs only when a quarter or more of the file is free space, and keeps its temporary copy on the USB drive instead of in the router's memory.
- Guest networks on more slots (3006.102's Guest Network Pro) are recognised as yours.

## 1.2.1

- **5 GHz scans on routers that refuse a full scan.** On a DFS channel, some drivers refuse every full 5 GHz scan ("Scan Rejected"), so the Spectrum, Site Survey and Channel Statistics stayed empty on 5 GHz. Some of them still take one channel at a time: an RT-BE88U took every single-channel scan. WiFi Insight now falls back to that when the full scan is refused: one channel after another, each retried for up to 20 seconds, giving up after three refused in a row or 150 seconds. Where the driver only takes one now and then, the next scan carries on where this one stopped, so the band fills in over a few scans. `scan`, Scan now and the syslog say so, for example "one channel at a time (full scan refused: wl said "Scan Rejected" for 20 s)". Routers whose full scans work aren't affected. Thanks to SashaSolitaire, EmeraldDeer and ColDen for the tests!
- **When scans fail, the page says why.** The Spectrum, Site Survey and Channel Statistics said "No scans yet" even when scans ran and the radio refused them. They now say what happened to the band's last scan, quoting the driver, and on 5 GHz that some routers refuse scans while on a DFS channel. When older scans are shown, the Spectrum subtitle mentions a failed scan after them.
- **A damaged database is reported, and `repair` fixes it.** After a power cut, a database on a USB drive can be damaged ("database disk image is malformed"), and charts get gaps or stop updating. WiFi Insight now notices, logs it once, and says so on the page and at the end of `status`. `wifiinsight.sh repair` rebuilds the database from everything still readable, with sampling and scans paused meanwhile, and keeps the damaged copy next to it (`wifiinsight.db.bad`). On a sound database it changes nothing. Thanks to ColDen for the report!
- *Networks per channel* shows *Yours* only when it heard other access points of yours (an AiMesh node, say). A router doesn't hear its own network when it scans, so without nodes the legend said *Yours* with nothing to show; the subtitle now explains that the shaded area is the router's channel.

## 1.2.0

- **Measured spectrum.** During every neighbour scan the radio also measures each channel it visits: airtime used by other networks, non-Wi-Fi energy (microwaves, baby monitors, Bluetooth…), energy it couldn't decode, and the noise floor. WiFi Insight now saves those figures, and the Spectrum heatmap, *Load per channel* and the quietest-channel suggestions use them instead of an estimate built from the networks heard. Tick *Others Wi-Fi*, *Non-Wi-Fi* and *Unclassified* to choose what counts, or switch to *Estimated* for the old view. Channel Statistics adds a **noise floor for every channel**. Figures are stored only for the channels a scan actually reached (the driver keeps older figures for the rest). The figures start with the first scan after updating (press *Scan now* to start sooner), and the page says so until then. Routers whose driver doesn't report per-channel figures keep the estimate. Tested on an RT-AX86U (3004.388); the GT-AX6000 (3006.102) reports the same figures, and WiFi Insight reads them too.
- **Complete scans on busy routers.** With traffic on the router's channel, the driver can stop a 5 GHz scan partway: an RT-AX86U reached channels 36–104 of 36–140 on every daytime scan, so networks and figures on the rest of the band were missing. WiFi Insight now notices and scans the remaining channels right away (one more short Wi-Fi hiccup, only when it happens). `scan`, Scan now and the syslog then say, for example, "stopped at 104 and finished with a second scan".
- **Weather-radar channels marked.** Channels 120, 124 and 128 (5600–5650 MHz) are shared with weather radars. Quietest options, the channel axes of the Spectrum, the Signal map and the Channel Statistics charts, the tooltips and the Networks table mark them, and wider blocks that include them, as *DFS · weather radar*, in the 135 countries and territories that allow Wi-Fi there (from the router's country code). When a block without them is about as quiet, Quietest options suggests that one instead. A note under Quietest options explains the radar check: before using a DFS channel the router listens for radar for 1 minute, or 10 minutes on the weather-radar channels in Europe and other countries on European rules.
- **Fixed: routers with a 6 GHz radio were refused** with "This router has two 5 GHz radios" (GT-AXE11000, RT-BE92U, RT-BE96U, GT-BE19000AI): the 6 GHz band code was read as 5 GHz. All three bands are read correctly now, including 320 MHz channels on 6 GHz, and Channel Statistics suggests the quietest 40 to 320 MHz blocks there. Thanks to BobWadd for the RT-BE96U report! Routers with two radios on the same band (GT-AX11000, ZenWiFi Pro XT12) are still refused for now.
- **A menu for the terminal, ready for amtm.** Run `/jffs/addons/wifiinsight/wifiinsight.sh` with no arguments for a menu: status, scan now, collection (on, scans paused or off), update, reinstall, debug report, amtm updates on or off, and uninstall (it asks first). amtm opens the same menu.
- **amtm can update WiFi Insight** (`amtmupdate`) along with your other scripts. It installs the latest release, prints two lines and logs the details to `/tmp/wifiinsight/amtmupdate.log`. To keep amtm from updating it, choose *Turn amtm updates off* in the menu (or set `AMTM_UPDATE=off` in the config); `update` still works.
- **Try unreleased changes:** `wifiinsight.sh update dev` installs the newest code on `main` (`update dev <branch>` for another branch of this repository; pull requests from forks are refused), keeping your settings and history; menu option 8 does the same. `status`, `debug` and the page's footer say when a development version is installed. `update` and amtm only ever install releases, and take a development version back to the latest release.
- New command: `wifiinsight.sh collection on|paused|off`, the same as Settings → Collection on the page.
- Updating no longer runs an extra neighbour scan when you already have history, so `update` finishes sooner without a Wi-Fi hiccup.
- The page: card descriptions sit on one line under the title, the Spectrum and *Load per channel* subtitles are shorter, the footer is just the status line, and DFS and radar are only mentioned on 5 GHz (2.4 and 6 GHz have no DFS channels). `scan` and the syslog say how many channels were measured, and `debug` prints the radio's country code.

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
