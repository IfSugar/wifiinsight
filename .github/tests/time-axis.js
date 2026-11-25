// Helper for time-axis.sh: the page's own timeTicks() and tickFmt(), taken from wifiinsight.asp, checked in every IANA
// time zone over two years: every 7 h 13 min, and every 7 min from an hour before to 26 h after each clock change.
const fs = require('fs');
const page = fs.readFileSync(process.argv[2], 'utf8');
const grab = name => { const i = page.indexOf('function ' + name + '('); let d = 0, j = page.indexOf('{', i); for (; j < page.length; j++) { if (page[j] === '{') d++; else if (page[j] === '}' && !--d) break; } return page.slice(i, j + 1); };
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], MONS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function pad(n) { return (n < 10 ? '0' : '') + n; }
function hm(ts) { const d = new Date(ts * 1000); return pad(d.getHours()) + ':' + pad(d.getMinutes()); }
eval(grab('timeTicks')); eval(grab('tickFmt'));
const RANGES = { '10m': [600, 2, 4, 6], '1h': [3600, 10, 5, 7], '12h': [43200, 120, 5, 7], '1d': [86400, 180, 7, 9], '7d': [604800, 0, 6, 8], '30d': [2592000, 0, 5, 7] };
const zones = Intl.supportedValuesOf('timeZone'), T0 = Date.UTC(2026, 0, 1) / 1000, T1 = Date.UTC(2028, 0, 1) / 1000;
let cases = 0, fails = 0, shown = 0, changes = 0;
const midnightOf = d => new Date(d.getFullYear(), d.getMonth(), d.getDate());
for (const tz of zones) {
	process.env.TZ = tz;
	const off = t => new Date(t * 1000).getTimezoneOffset(), nows = [];
	for (let t = T0; t < T1; t += 7 * 3600 + 13 * 60) nows.push(t);
	for (let t = T0; t < T1; t += 3600) if (off(t) !== off(t + 3600)) { changes++; for (let n = t - 3600; n < t + 26 * 3600; n += 7 * 60) nows.push(n); }
	for (const now of nows) for (const [rng, [secs, mins, lo, hi]] of Object.entries(RANGES)) {
		cases++;
		const R = { from: now - secs, to: now, multi: secs > 86400, month: secs > 604800 }, t = timeTicks(R), bad = [];
		if (t.length < lo || t.length > hi) bad.push('count ' + t.length);
		t.forEach((v, i) => {
			const d = new Date(v * 1000);
			if (v < R.from || v > R.to) bad.push('outside');
			if (i && v <= t[i - 1]) bad.push('order');
			if (mins) { if (d.getSeconds() || (d.getHours() * 60 + d.getMinutes()) % mins) bad.push('at ' + hm(v)); }
			else {
				if (midnightOf(d).getTime() !== v * 1000) bad.push('not the start of a day ' + hm(v));   // midnight, or the day's first time where midnight is skipped
				if (i) { const a = new Date(t[i - 1] * 1000), days = Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 864e5); if (days !== (rng === '7d' ? 1 : 5)) bad.push('step ' + days); }
				const want = R.month ? MONS[d.getMonth()] + ' ' + d.getDate() : DAYS[d.getDay()] + ' ' + d.getDate();
				if (tickFmt(R)(v) !== want) bad.push('label ' + tickFmt(R)(v));
			}
		});
		if (bad.length) { fails++; if (shown++ < 15) console.log('FAIL', tz, rng, new Date(now * 1000).toISOString(), bad.slice(0, 3).join(', '), '| ticks', t.map(hm).join(' ')); }
	}
}
console.log(zones.length + ' zones, ' + changes + ' clock changes in 2026-2027, ' + cases + ' cases, ' + fails + ' failing');
process.exit(fails ? 1 : 0);
