# Security policy

WiFi Insight runs as root on your router, adds a page to its web interface and reads data that anyone nearby can
influence (every network name in range ends up in it), so security problems matter. Thanks for reporting them
responsibly.

## Reporting a problem

Report it privately through GitHub: **[Report a vulnerability](https://github.com/IfSugar/wifiinsight/security/advisories/new)**.
Please don't open a public issue, discussion or pull request for it.

Useful to include: your router model, firmware version, WiFi Insight version (`wifiinsight.sh version`) and the steps
to reproduce. Never include router passwords, your WAN IP address or DDNS name. Your own and your neighbours'
network names and MAC addresses aren't needed: replace them with made-up ones.

You'll get an answer within a few days. Please allow up to 90 days for a fix before publishing details; problems that
put users at risk right now are fixed and disclosed sooner.

## What's in scope

- **Network names and scan results.** Anyone in range can broadcast any network name. Anything that lets one run
  script in the WiFi Insight page, run something through the router's page templates (`<% … %>`), break the database
  or the data files, or run a command on the router.
- **The page and its data files.** Reading the data files (`/ext/wifiinsight/*.htm`) or the page without the router
  login, or getting the page to send data anywhere.
- **Settings and actions.** Changing settings, starting scans or other actions without the router login, or a
  setting value that ends up run as shell code (the config file is read by the shell).
- **The script on the router.** Anything that makes it write outside its own folders, follow a link planted in
  `/tmp`, or run with someone else's input as code.
- **Install and update.** Getting a router to run code that isn't from this repository. Updates download from GitHub
  over HTTPS; Chart.js is checked against its SHA-256 at install, and the CDN fallback uses Subresource Integrity.
- **The release workflow.**

## Not in scope

- Asuswrt-Merlin itself, amtm, Entware packages and other addons: report those to their projects (the
  [SNBForums Asuswrt-Merlin AddOns forum](https://www.snbforums.com/forums/asuswrt-merlin-addons.60/) is a good
  place to start).
- Anything that needs someone who can already log in to the router's web interface or over SSH: they can see the
  same neighbouring networks and run any command anyway.
- The brief Wi-Fi hiccup during a neighbour scan: it's documented, and scans can be made less frequent or turned off.

## Supported versions

Only the latest release gets fixes. Update with `/jffs/addons/wifiinsight/wifiinsight.sh update`.
