# Changelog

What changed in each release of WiFi Insight. The release workflow copies a version's section into its GitHub release notes, so write for people running the addon.

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
