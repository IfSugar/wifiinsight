# Changelog

What changed in each release of WiFi Insight. The release workflow copies a version's section into its GitHub release notes, so write for people running the addon.

## 1.0.7

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
