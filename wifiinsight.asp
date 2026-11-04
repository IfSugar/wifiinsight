<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge"/>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
<meta http-equiv="Pragma" content="no-cache"/>
<meta http-equiv="Expires" content="-1"/>
<link rel="shortcut icon" href="images/favicon.png"/>
<link rel="icon" href="images/favicon.png"/>
<title>WiFi Insight</title>
<!-- wifiinsight-version: 1.0.2 (must match VERSION in wifiinsight.sh) -->
<link rel="stylesheet" type="text/css" href="index_style.css"/>
<link rel="stylesheet" type="text/css" href="form_style.css"/>
<script type="text/javascript" src="/js/jquery.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script type="text/javascript" src="/validator.js"></script>
<style>
#wi {
	--surface: #2b3539;
	--line: rgba(255,255,255,0.08);
	--axis: #4a585d;
	--ink: #f0efec;
	--ink-2: #c3c2b7;
	--muted: #93a9b1;
	--sel: #4d6b75;
	--others: #3987e5;
	--nonwifi: #d95926;
	--yours: #199e70;
	--rx: #9085e9;
	--unclass: #c98500;
	--plcp: #d55181;
	--fail: #e66767;
	--accent: #ffcc00;
	font-family: system-ui, -apple-system, "Segoe UI", Arial, sans-serif;
	color: var(--ink);
	font-size: 12px;
}
#wi * { box-sizing: border-box; }
#wi code { background: #1f282b; padding: 1px 5px; border-radius: 4px; font-size: 11px; }
#wi .tabs { display: flex; gap: 2px; border-bottom: 1px solid var(--axis); margin: 2px 0 12px; }
#wi .tabs button { background: none; border: 0; border-bottom: 2px solid transparent; color: var(--ink-2); font: inherit; font-size: 13px; padding: 8px 12px 7px; cursor: pointer; margin-bottom: -1px; }
#wi .tabs button:hover { color: var(--ink); }
#wi .tabs button.on { color: #fff; border-bottom-color: var(--accent); font-weight: 600; }
#wi .bar { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin: 0 0 12px; }
#wi .seg { display: inline-flex; background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 2px; }
#wi .seg button { background: none; border: 0; color: var(--ink-2); font: inherit; padding: 5px 11px; border-radius: 4px; cursor: pointer; }
#wi .seg button:hover { color: var(--ink); background: rgba(255,255,255,0.05); }
#wi .seg button.on { background: var(--sel); color: #fff; font-weight: 600; }
#wi .grow { flex: 1; }
#wi .btn { background: var(--surface); border: 1px solid var(--axis); color: var(--ink); font: inherit; padding: 6px 12px; border-radius: 6px; cursor: pointer; }
#wi .btn:hover { border-color: var(--muted); }
#wi .btn.primary { background: var(--sel); border-color: var(--sel); color: #fff; font-weight: 600; }
#wi .btn[disabled] { opacity: .55; cursor: default; }
#wi .view { display: none; }
#wi .view.on { display: block; }
#wi .tiles { display: grid; grid-template-columns: 1.35fr repeat(5, 1fr); gap: 8px; margin-bottom: 12px; }
#wi .tile { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; min-width: 0; }
#wi .tile .k { color: var(--muted); font-size: 11px; margin-bottom: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
#wi .tile .v { font-size: 20px; font-weight: 600; line-height: 1.15; white-space: nowrap; }
#wi .tile .v small { font-size: 12px; font-weight: 400; color: var(--ink-2); }
#wi .tile .s { color: var(--ink-2); font-size: 11px; margin-top: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
#wi .sw { display: inline-block; width: 10px; height: 3px; border-radius: 2px; vertical-align: middle; margin-right: 5px; }
#wi .sw.dash { background: repeating-linear-gradient(90deg, var(--fail) 0 3px, transparent 3px 5px) !important; }
#wi .sq { display: inline-block; width: 9px; height: 9px; border-radius: 2px; vertical-align: -1px; margin-right: 5px; }
#wi .card { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 12px 14px 10px; margin-bottom: 12px; min-width: 0; }
#wi .card h3 { margin: 0; font-size: 13px; font-weight: 600; color: var(--ink); }
#wi .card .sub { color: var(--muted); font-size: 11px; margin-top: 2px; line-height: 1.4; }
#wi .head { display: flex; align-items: flex-start; gap: 12px; margin-bottom: 8px; }
#wi .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
#wi .grid2 .card { margin-bottom: 0; }
#wi .gridgap { height: 12px; }
#wi .legend { display: flex; gap: 12px; flex-wrap: wrap; justify-content: flex-end; }
#wi .legend label, #wi .legend span.li { display: inline-flex; align-items: center; gap: 5px; color: var(--ink-2); user-select: none; white-space: nowrap; }
#wi .legend label { cursor: pointer; }
#wi .legend input { margin: 0; accent-color: var(--sel); }
#wi .chartbox { position: relative; height: 230px; }
#wi .chartbox.sm { height: 170px; }
#wi .empty { color: var(--muted); text-align: center; padding: 40px 0; }
#wi .rel { position: relative; }
#wi canvas.full { display: block; width: 100%; }
#wi .foot { display: flex; align-items: center; gap: 16px; margin-top: 8px; color: var(--ink-2); flex-wrap: wrap; }
#wi .ramp { display: inline-flex; align-items: center; gap: 6px; }
#wi .ramp i { display: inline-block; width: 120px; height: 8px; border-radius: 4px; }
#wi .tip { position: absolute; pointer-events: none; background: #1c2427; border: 1px solid var(--axis); border-radius: 6px; padding: 7px 9px; font-size: 11px; line-height: 1.5; color: var(--ink); white-space: nowrap; z-index: 5; display: none; box-shadow: 0 4px 14px rgba(0,0,0,.35); }
#wi .tip .m { color: var(--muted); }
#wi table.t { width: 100%; border-collapse: collapse; }
#wi table.t th { text-align: left; color: var(--muted); font-weight: 500; font-size: 11px; padding: 6px 8px; border-bottom: 1px solid var(--axis); white-space: nowrap; }
#wi table.t th.sort { cursor: pointer; }
#wi table.t th.sort:hover { color: var(--ink); }
#wi table.t td { padding: 6px 8px; border-bottom: 1px solid var(--line); color: var(--ink); vertical-align: middle; }
#wi table.t td.num, #wi table.t th.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
#wi table.t td.mono { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 11px; color: var(--ink-2); }
#wi table.t td.dim { color: var(--muted); }
#wi table.t tr:last-child td { border-bottom: 0; }
#wi .tag { display: inline-block; padding: 2px 7px; border-radius: 10px; font-size: 11px; background: #3e4d52; color: var(--ink); white-space: nowrap; }
#wi .tag.radar { background: #6b2b2b; }
#wi .tag.manual { background: #2f4f6b; }
#wi .tag.auto, #wi .tag.bandwidth { background: #2c5a49; }
#wi .tag.restart, #wi .tag.scheduled { background: #4a4a3a; }
#wi .pill { display: inline-block; margin-left: 6px; padding: 1px 6px; border-radius: 8px; font-size: 10px; background: var(--sel); color: #fff; vertical-align: 1px; white-space: nowrap; }
#wi .pill.dfs { background: #3e4d52; color: var(--ink-2); }
#wi .pill.cur { background: #5c4e14; color: #ffe27a; }
#wi .sig { display: inline-block; width: 42px; height: 5px; background: #3e4d52; border-radius: 3px; vertical-align: middle; margin-right: 6px; overflow: hidden; }
#wi .sig i { display: block; height: 100%; background: var(--ink-2); border-radius: 3px; }
#wi .more { background: none; border: 0; color: var(--muted); font: inherit; cursor: pointer; padding: 6px 0 0; text-decoration: underline; }
#wi .note { color: var(--muted); font-size: 11px; line-height: 1.5; margin: 4px 2px 0; }
#wi .warn { background: #4a3d22; border: 1px solid #6b5728; color: #f3e2b4; border-radius: 6px; padding: 8px 10px; margin-bottom: 12px; display: none; }
#wi .form { display: grid; grid-template-columns: 200px 1fr; gap: 14px 16px; align-items: start; }
#wi .form .lbl { color: var(--ink); padding-top: 6px; }
#wi .form .hint { color: var(--muted); font-size: 11px; margin-top: 4px; line-height: 1.4; }
#wi select, #wi input[type=text] { background: #1f282b; border: 1px solid var(--axis); color: var(--ink); font: inherit; padding: 6px 8px; border-radius: 6px; }
#wi input[type=text] { width: 100%; max-width: 380px; }
#wi .saved { color: #7fd1ad; margin-left: 10px; display: none; }
</style>
<script type="text/javascript">
var custom_settings = <% get_custom_settings(); %>;
/* Everything below is private, so nothing clashes with the firmware's globals (jQuery's $, store, ...).
   Only initial() (called by <body onload>) and the WiFiInsight object (used by the page's buttons) are global. */
(function () {
var WI = {
	base: '/ext/wifiinsight/',
	live: null, week: null, scans: null,
	view: 'insight', band: '5g', range: '1h',
	charts: {}, hidden: {},
	showMesh: false, showDfs: true, showActive: true, allEvents: false,
	sortKey: 'rssi', sortDir: -1
};
var RANGES = { '10m': 600, '1h': 3600, '12h': 43200, '1d': 86400, '7d': 604800 };
var BAND_NAME = { '2g': '2.4 GHz', '5g': '5 GHz', '6g': '6 GHz' };
var TAGS = {
	initial: 'Monitoring started', restart: 'Router restarted', scheduled: 'Scheduled reboot',
	manual: 'Manually configured', auto: 'Optimized automatically', bandwidth: 'Adaptive bandwidth',
	radar: 'Regulatory (RADAR)', changed: 'Channel changed'
};
var PHY = { be: 'Wi-Fi 7', ax: 'Wi-Fi 6', ac: 'Wi-Fi 5', n: 'Wi-Fi 4', g: 'Legacy', a: 'Legacy' };
var RAMP = ['#eff4fc', '#d8e7fd', '#c3d9fa', '#afccf5', '#9bbff0', '#88b2ea', '#75a4e3', '#6297dd', '#4e8ad5', '#397dce', '#216fc6', '#0062ba'];   /* clean (near-white) -> busy (deep blue), even OKLab lightness steps */
var C = { others: '#3987e5', nonwifi: '#d95926', yours: '#199e70', rx: '#9085e9', unclass: '#c98500', plcp: '#d55181', fail: '#e66767', idle: '#46555a', grid: 'rgba(255,255,255,0.07)', tick: '#93a9b1', ink2: '#c3c2b7', surface: '#2b3539' };
/* live sample columns / 15-minute aggregate columns */
var FL = { obss: 1, nocat: 2, tx: 3, inbss: 4, idle: 5, glitch: 6, noise: 7, nopkt: 11, doze: 12, txop: 13, goodtx: 14, badtx: 15, badplcp: 16, knoise: 17 };
var FW = { obss: 1, nocat: 2, yours: 3, idle: 4, glitch: 6, badplcp: 7, noise: 8, nopkt: 9, tx: 10, inbss: 11, goodtx: 12, badtx: 13 };

function store(k, v) { try { if (v === undefined) return localStorage.getItem('wi_' + k); localStorage.setItem('wi_' + k, v); } catch (e) { return null; } }
function $(id) { return document.getElementById(id); }
function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
function pad(n) { return (n < 10 ? '0' : '') + n; }
function hm(ts) { var d = new Date(ts * 1000); return pad(d.getHours()) + ':' + pad(d.getMinutes()); }
var DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
var MONS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function when(ts) {
	var d = new Date(ts * 1000), n = new Date();
	var day0 = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime() / 1000;
	if (ts >= day0) return 'Today ' + hm(ts);
	if (ts >= day0 - 86400) return 'Yesterday ' + hm(ts);
	return MONS[d.getMonth()] + ' ' + d.getDate() + ' ' + hm(ts);
}
function ago(sec) {
	if (sec < 90) return Math.max(0, Math.round(sec)) + ' s ago';
	if (sec < 5400) return Math.round(sec / 60) + ' min ago';
	if (sec < 172800) return Math.round(sec / 3600) + ' h ago';
	return Math.round(sec / 86400) + ' days ago';
}
function dur(ms) {
	var m = Math.floor(ms / 60000), h = Math.floor(m / 60), d = Math.floor(h / 24);
	if (d > 0) return d + 'd ' + (h % 24) + 'h';
	if (h > 0) return h + 'h ' + pad(m % 60) + 'm';
	return m + ' min';
}
function nowTs() { return WI.live ? WI.live.generated : Date.now() / 1000; }
function radio() {
	var r = (WI.live && WI.live.radios) || [];
	for (var i = 0; i < r.length; i++) if (r[i].band === WI.band) return r[i];
	return null;
}
function chans() { var r = radio(); return (r && r.channels && r.channels.length) ? r.channels : []; }
function spanOf(center, width) {
	var n = Math.max(1, Math.round(width / 20)), out = [];
	for (var i = 0; i < n; i++) out.push(center - (n - 1) * 2 + i * 4);
	return out;
}
function isDfs(ch) { return WI.band === '5g' && ch >= 52 && ch <= 144; }
function freq(ch) {
	if (WI.band === '2g') return ch === 14 ? 2484 : 2407 + 5 * ch;
	if (WI.band === '6g') return 5950 + 5 * ch;
	return 5000 + 5 * ch;
}

function getJSON(name) {
	return fetch(WI.base + name + '?_=' + Date.now(), { cache: 'no-store', credentials: 'same-origin' })
		.then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
		.then(function (t) { return JSON.parse(t); });
}
function loadAll(what) {
	var jobs = [];
	if (!what || what.live) jobs.push(getJSON('live.htm').then(function (d) { WI.live = d; }));
	/* scans and week files can be missing for a minute after a reboot: keep what we have */
	if (!what || what.scans) jobs.push(getJSON('scans.htm').then(function (d) { WI.scans = d; }, function () {}));
	if (!what || what.week) jobs.push(getJSON('week.htm').then(function (d) { WI.week = d; }, function () {}));
	return Promise.all(jobs).then(function () { $('wiWarn').style.display = 'none'; render(); })
		.catch(function () {
			var w = $('wiWarn');
			w.innerHTML = 'No data yet. If you just installed, give it a minute. Otherwise check that the USB drive is mounted and run <code>/jffs/addons/wifiinsight/wifiinsight.sh status</code> over SSH.';
			w.style.display = 'block';
		});
}

/* ---------- time series helpers ---------- */
function rangeInfo() { var to = nowTs(); return { from: to - RANGES[WI.range], to: to, multi: WI.range === '7d' }; }
function tickFmt(multi) {
	return function (v) { var d = new Date(v * 1000); return multi ? DAYS[d.getDay()] + ' ' + pad(d.getHours()) + 'h' : hm(v); };
}
/* Build {x,y} arrays for the given fields over the selected range; inserts nulls across gaps. */
function series(fields) {
	var R = rangeInfo(), out = {}, last = null, rows, map, step;
	fields.forEach(function (f) { out[f] = []; });
	if (R.multi) { rows = (WI.week && WI.week.agg && WI.week.agg[WI.band]) || []; map = FW; step = (WI.week && WI.week.bucket) || 900; }
	else { rows = (WI.live && WI.live.samples && WI.live.samples[WI.band]) || []; map = FL; step = (WI.live && WI.live.sample_interval) || 30; }
	var n = 0;
	for (var i = 0; i < rows.length; i++) {
		var r = rows[i];
		if (r[0] < R.from) continue;
		if (last !== null && r[0] - last > step * 4) fields.forEach(function (f) { out[f].push({ x: last + step, y: null }); });
		fields.forEach(function (f) {
			var v;
			if (f === 'yours') v = R.multi ? r[FW.yours] : (r[FL.tx] || 0) + (r[FL.inbss] || 0);
			else v = r[map[f]];
			out[f].push({ x: r[0], y: v == null ? null : v });
		});
		last = r[0]; n++;
	}
	out._n = n; out._R = R;
	return out;
}
function latestSample() {
	var s = (WI.live && WI.live.samples && WI.live.samples[WI.band]) || [];
	return s.length ? s[s.length - 1] : null;
}

var eventMarkers = {
	id: 'wiEvents',
	afterDatasetsDraw: function (chart) {
		var evs = chart.$wiEvents || [], x = chart.scales.x, a = chart.chartArea, ctx = chart.ctx;
		if (!evs.length) return;
		ctx.save();
		ctx.setLineDash([3, 3]); ctx.lineWidth = 1;
		ctx.font = '10px system-ui, -apple-system, Segoe UI, sans-serif'; ctx.textBaseline = 'top';
		var k = 0, vis = evs.filter(function (e) { var p = x.getPixelForValue(e[0]); return p >= a.left && p <= a.right; }).length;
		for (var i = 0; i < evs.length; i++) {
			var px = x.getPixelForValue(evs[i][0]);
			if (px < a.left || px > a.right) continue;
			var radar = evs[i][2] === 'radar';
			ctx.strokeStyle = radar ? C.fail : 'rgba(240,239,236,0.45)';
			ctx.beginPath(); ctx.moveTo(px, a.top); ctx.lineTo(px, a.bottom); ctx.stroke();
			if (vis > 4 && !radar) continue;   // too many to label; the event list has them
			ctx.fillStyle = radar ? C.fail : C.ink2;
			var lbl = TAGS[evs[i][2]] || evs[i][2], w = ctx.measureText(lbl).width;
			ctx.fillText(lbl, Math.min(px + 4, a.right - w), a.top + 2 + (k++ % 3) * 12);
		}
		ctx.restore();
	}
};

/* Generic Chart.js wrapper: destroys and rebuilds (charts are small, animation is off). */
function drawChart(key, boxId, type, datasets, o) {
	o = o || {};
	var box = $(boxId);
	if (WI.charts[key]) { WI.charts[key].destroy(); delete WI.charts[key]; }
	if (typeof Chart === 'undefined') { box.innerHTML = '<div class="empty">Loading chart library…</div>'; return null; }
	if (o.empty) { box.innerHTML = '<div class="empty">' + o.empty + '</div>'; return null; }
	box.innerHTML = '<canvas></canvas>';
	datasets.forEach(function (d, i) {
		if (type === 'line') {
			d.borderWidth = d.borderWidth || 2; d.pointRadius = 0; d.pointHoverRadius = 4; d.pointHoverBorderWidth = 2;
			d.pointHoverBorderColor = C.surface; d.tension = 0.2; d.spanGaps = false;
			if (d.backgroundColor === undefined) d.backgroundColor = d.borderColor;
		}
		if (WI.hidden[key + ':' + d.label]) d.hidden = true;
	});
	var scales = {
		x: o.x || { type: 'linear', grid: { color: C.grid, drawTicks: false }, border: { color: '#4a585d' }, ticks: { color: C.tick, maxTicksLimit: 8, padding: 6, font: { size: 11 } } },
		y: { grid: { color: C.grid, drawTicks: false }, border: { display: false }, ticks: { color: C.tick, padding: 6, font: { size: 11 } } }
	};
	if (o.yMin !== undefined) scales.y.min = o.yMin;
	if (o.yMax !== undefined) scales.y.max = o.yMax;
	if (o.yFmt) scales.y.ticks.callback = o.yFmt;
	if (o.yStep) scales.y.ticks.stepSize = o.yStep;
	if (o.stacked) { scales.y.stacked = true; scales.x.stacked = true; }
	if (o.R) { scales.x.min = o.R.from; scales.x.max = o.R.to; scales.x.ticks.callback = tickFmt(o.R.multi); }
	var ch = new Chart(box.firstChild, {
		type: type,
		data: { labels: o.labels, datasets: datasets },
		options: {
			animation: false, responsive: true, maintainAspectRatio: false, parsing: type === 'bar', normalized: true,
			interaction: { mode: 'index', intersect: false },
			layout: { padding: { top: 4, right: 6 } },
			scales: scales,
			plugins: {
				legend: { display: false },
				tooltip: {
					backgroundColor: '#1c2427', borderColor: '#4a585d', borderWidth: 1, titleColor: '#f0efec', bodyColor: '#f0efec',
					padding: 9, boxWidth: 10, boxHeight: 3,
					filter: function (it) { return it.parsed.y != null; },
					callbacks: {
						title: o.ttTitle || function (items) { return items.length && o.R ? when(items[0].parsed.x) + (o.R.multi ? ' (15-min average)' : '') : (items[0] ? items[0].label : ''); },
						label: o.ttLabel || function (it) { return ' ' + it.dataset.label + ': ' + it.parsed.y + (o.unit || ''); }
					}
				}
			}
		},
		plugins: o.plugins || []
	});
	if (o.events) ch.$wiEvents = o.events;
	ch.update('none');
	WI.charts[key] = ch;
	return ch;
}
function legendHTML(key, items) {   // items: [label, color, toggleable, dashed]
	return items.map(function (it) {
		var sw = '<span class="sw' + (it[3] ? ' dash' : '') + '" style="background:' + it[1] + '"></span>';
		if (!it[2]) return '<span class="li">' + sw + esc(it[0]) + '</span>';
		var on = !WI.hidden[key + ':' + it[0]];
		return '<label><input type="checkbox"' + (on ? ' checked' : '') + ' onchange="WiFiInsight.toggleSeries(\'' + key + '\',\'' + it[0] + '\',this.checked)"/>' + sw + esc(it[0]) + '</label>';
	}).join('');
}
function toggleSeries(key, label, on) { WI.hidden[key + ':' + label] = !on; renderView(); }
function bandEvents() { return ((WI.live && WI.live.events) || []).filter(function (e) { return e[1] === WI.band || e[1] === 'all'; }); }
function pctMax(sets) {
	var m = 0;
	sets.forEach(function (s) { if (WI.hidden[s[0]]) return; s[1].forEach(function (p) { if (p.y != null && p.y > m) m = p.y; }); });
	return Math.min(100, Math.max(20, Math.ceil((m + 5) / 10) * 10));
}
function pctFmt(v) { return v + '%'; }

/* =================== INSIGHT =================== */
function renderInsight() {
	renderTiles();
	var s = series(['obss', 'nocat', 'yours']);
	var yMax = pctMax([['ins:Others Wi-Fi', s.obss], ['ins:Non-Wi-Fi', s.nocat], ['ins:Your network', s.yours]]);
	$('wiInsLegend').innerHTML = legendHTML('ins', [['Others Wi-Fi', C.others, 1], ['Non-Wi-Fi', C.nonwifi, 1], ['Your network', C.yours, 1]]);
	drawChart('ins', 'wiInsChart', 'line', [
		{ label: 'Others Wi-Fi', data: s.obss, borderColor: C.others },
		{ label: 'Non-Wi-Fi', data: s.nocat, borderColor: C.nonwifi },
		{ label: 'Your network', data: s.yours, borderColor: C.yours }
	], { R: s._R, yMin: 0, yMax: yMax, yStep: yMax > 50 ? 20 : 10, yFmt: pctFmt, unit: '%', events: bandEvents(), plugins: [eventMarkers],
		empty: s._n ? null : 'No samples in this range yet. They arrive every ' + ((WI.live && WI.live.sample_interval) || 30) + ' seconds.' });
	renderHeat();
	renderEvents();
}
function renderTiles() {
	var r = radio(), last = latestSample(), html = '';
	if (r) {
		var sub = r.auto ? 'Auto' : 'Manual';
		if (r.dfs_state && r.dfs_state.indexOf('ISM') >= 0 && r.dfs_ms) sub += ' · DFS ' + dur(r.dfs_ms);
		else if (r.dfs_state && r.dfs_state.indexOf('CAC') >= 0) sub += ' · DFS radar check';
		html += tile('Channel', r.ctl + ' <small>· ' + r.width + ' MHz</small>', sub);
	} else html += tile('Channel', '–', 'Radio off');
	if (last && nowTs() - last[0] < 600) {
		var tot = (last[1] || 0) + (last[2] || 0);
		html += tile('Interference', tot + '<small>%</small>', tot < 10 ? 'Low' : tot < 30 ? 'Moderate' : 'High', 'In-channel interference: others Wi-Fi + non-Wi-Fi');
		html += tile('<span class="sw" style="background:' + C.others + '"></span>Others Wi-Fi', last[1] + '<small>%</small>', 'Neighbours', 'Airtime used by networks that are not yours');
		html += tile('<span class="sw" style="background:' + C.nonwifi + '"></span>Non-Wi-Fi', last[2] + '<small>%</small>', (last[6] == null ? '–' : last[6]) + ' glitches', 'Energy from non-Wi-Fi devices; receive glitches in the last sample');
		html += tile('Idle', last[5] + '<small>%</small>', '<span class="sw" style="background:' + C.yours + '"></span>Yours ' + ((last[3] || 0) + (last[4] || 0)) + '%', 'Idle airtime; your own traffic share');
		html += tile('Noise', (r && r.noise != null ? r.noise : last[7]) + ' <small>dBm</small>', ago(nowTs() - last[0]), 'Noise floor');
	} else {
		['Interference', 'Others Wi-Fi', 'Non-Wi-Fi', 'Idle', 'Noise'].forEach(function (k) { html += tile(k, '–', 'No recent sample'); });
	}
	$('wiTiles').innerHTML = html;
}
function tile(k, v, s, title) { return '<div class="tile"' + (title ? ' title="' + esc(title) + '"' : '') + '><div class="k">' + k + '</div><div class="v">' + v + '</div><div class="s">' + s + '</div></div>'; }

function rampColor(v) {
	if (v <= 0.5) return RAMP[0];
	var t = Math.min(1, v / 100) * (RAMP.length - 2);
	return RAMP[1 + Math.min(RAMP.length - 2, Math.round(t))];
}
/* scans grouped by timestamp, newest first, within the range (falls back to the latest scan) */
function scanRows() {
	var all = (WI.scans && WI.scans.scans && WI.scans.scans[WI.band]) || [];
	var from = nowTs() - RANGES[WI.range], byTs = {}, order = [];
	for (var i = 0; i < all.length; i++) {
		var r = all[i];   // ts,ch,score,aps,best,own
		if (!byTs[r[0]]) { byTs[r[0]] = {}; order.push(r[0]); }
		byTs[r[0]][r[1]] = r;
	}
	order.sort(function (a, b) { return b - a; });
	var inRange = order.filter(function (t) { return t >= from; }), latestOnly = false;
	if (!inRange.length && order.length) { inRange = [order[0]]; latestOnly = true; }
	return { rows: inRange.map(function (t) { return { ts: t, cells: byTs[t] }; }), latestOnly: latestOnly };
}
function noScansMsg() {
	return (WI.scans && WI.scans.scan_interval === 0) ? 'Neighbour scans are switched off. Turn them on in Settings, or press <b>Scan now</b>.' : 'No scans yet. Press <b>Scan now</b> or wait for the next scheduled scan.';
}
function prepCanvas(cv, cssH) {
	var cssW = cv.parentNode.clientWidth || 700, dpr = window.devicePixelRatio || 1;
	cv.width = Math.round(cssW * dpr); cv.height = Math.round(cssH * dpr); cv.style.height = cssH + 'px';
	var ctx = cv.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, cssW, cssH);
	ctx.font = '11px system-ui, -apple-system, Segoe UI, sans-serif';
	return { ctx: ctx, w: cssW, h: cssH };
}
function renderHeat() {
	var cv = $('wiHeat'), r = radio(), info = scanRows(), rows = info.rows, ch = chans();
	if (!rows.length || !ch.length) {
		cv.style.display = 'none'; $('wiHeatEmpty').style.display = 'block'; $('wiHeatEmpty').innerHTML = noScansMsg(); $('wiHeatSub').textContent = '';
		WI.heatGeo = null; return;
	}
	cv.style.display = 'block'; $('wiHeatEmpty').style.display = 'none';
	var padL = WI.range === '7d' ? 56 : 46, padB = 34, padT = 4, padR = 4;
	var rowH = Math.min(20, 220 / rows.length);
	if (rowH >= 3) rowH = Math.floor(rowH);
	var gridH = rowH * rows.length;
	var P = prepCanvas(cv, Math.ceil(gridH) + padT + padB), ctx = P.ctx;
	var colW = (P.w - padL - padR) / ch.length, gx = colW > 8 ? 2 : 1, gy = rowH >= 8 ? 2 : (rowH >= 5 ? 1 : 0);
	for (var i = 0; i < rows.length; i++) for (var j = 0; j < ch.length; j++) {
		var c = rows[i].cells[ch[j]], v = c ? c[2] + (WI.showMesh ? c[5] : 0) : 0;
		ctx.fillStyle = c ? rampColor(v) : '#2f3a3e';
		if (rowH < 3) ctx.fillRect(padL + j * colW + gx / 2, padT + i * rowH, colW - gx, rowH + 0.6);
		else roundRect(ctx, padL + j * colW + gx / 2, padT + i * rowH + gy / 2, colW - gx, rowH - gy, rowH >= 8 ? 3 : 1);
	}
	axisChannels(ctx, ch, padL, colW, padT + gridH);
	ctx.fillStyle = C.tick; ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
	var lblEvery = Math.max(1, Math.ceil(18 / rowH));
	for (var k = 0; k < rows.length; k += lblEvery) {
		if (padT + k * rowH + rowH / 2 > padT + gridH - 6 && k > 0) break;
		var dt = new Date(rows[k].ts * 1000);
		ctx.fillText(WI.range === '7d' ? DAYS[dt.getDay()] + ' ' + pad(dt.getHours()) + 'h' : hm(rows[k].ts), padL - 6, padT + k * rowH + rowH / 2);
	}
	if (WI.showActive && r) activeBox(ctx, ch, r, padL, colW, padT, gridH);
	WI.heatGeo = { padL: padL, padT: padT, colW: colW, rowH: rowH, rows: rows, chans: ch };
	$('wiHeatSub').textContent = (info.latestOnly ? 'Latest scan, ' : rows.length + ' scan' + (rows.length > 1 ? 's' : '') + ' in range, newest ') + ago(nowTs() - rows[0].ts) + '. Estimated from nearby networks’ signal strength and the load they report.';
}
function axisChannels(ctx, ch, padL, colW, y0) {
	ctx.fillStyle = C.tick; ctx.textAlign = 'center'; ctx.textBaseline = 'top';
	var every = colW < 22 ? 2 : 1;
	ch.forEach(function (c, j) { if (j % every === 0) ctx.fillText(c, padL + (j + 0.5) * colW, y0 + 5); });
	if (!WI.showDfs || WI.band !== '5g') return;
	ctx.strokeStyle = 'rgba(147,169,177,0.6)'; ctx.lineWidth = 1; ctx.setLineDash([]);
	var runs = [], cur = null;
	ch.forEach(function (c, j) { if (isDfs(c)) { if (!cur) { cur = { a: j, b: j }; runs.push(cur); } else cur.b = j; } else cur = null; });
	runs.forEach(function (run) {
		var x1 = padL + run.a * colW + 2, x2 = padL + (run.b + 1) * colW - 2, y = y0 + 22;
		ctx.beginPath(); ctx.moveTo(x1, y - 3); ctx.lineTo(x1, y); ctx.lineTo(x2, y); ctx.lineTo(x2, y - 3); ctx.stroke();
		ctx.textAlign = 'center'; ctx.textBaseline = 'top'; ctx.fillText('DFS', (x1 + x2) / 2, y + 1);
	});
}
function activeBox(ctx, ch, r, padL, colW, top, h) {
	var sp = spanOf(r.center, r.width).filter(function (c) { return ch.indexOf(c) >= 0; });
	if (!sp.length && ch.indexOf(r.ctl) >= 0) sp = [r.ctl];
	if (!sp.length) return;
	var a = ch.indexOf(sp[0]), b = ch.indexOf(sp[sp.length - 1]);
	ctx.strokeStyle = '#ffcc00'; ctx.lineWidth = 2; ctx.setLineDash([]);
	ctx.strokeRect(padL + a * colW + 1, top, (b - a + 1) * colW - 2, h);
}
function roundRect(ctx, x, y, w, h, r) {
	if (w <= 0 || h <= 0) return;
	r = Math.min(r, w / 2, h / 2);
	ctx.beginPath(); ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.quadraticCurveTo(x + w, y, x + w, y + r);
	ctx.lineTo(x + w, y + h - r); ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h); ctx.lineTo(x + r, y + h);
	ctx.quadraticCurveTo(x, y + h, x, y + h - r); ctx.lineTo(x, y + r); ctx.quadraticCurveTo(x, y, x + r, y); ctx.closePath(); ctx.fill();
}
function placeTip(tip, host, x, y) {
	tip.style.display = 'block';
	var tx = x + 14, ty = y + 12;
	if (tx + tip.offsetWidth > host.clientWidth) tx = x - tip.offsetWidth - 10;
	tip.style.left = tx + 'px'; tip.style.top = ty + 'px';
}
function heatHover(ev) {
	var g = WI.heatGeo, tip = $('wiTip');
	if (!g) return;
	var rect = ev.target.getBoundingClientRect(), x = ev.clientX - rect.left, y = ev.clientY - rect.top;
	var j = Math.floor((x - g.padL) / g.colW), i = Math.floor((y - g.padT) / g.rowH);
	if (j < 0 || j >= g.chans.length || i < 0 || i >= g.rows.length) { tip.style.display = 'none'; return; }
	var ch = g.chans[j], row = g.rows[i], c = row.cells[ch];
	var h = '<b>Channel ' + ch + '</b>' + (isDfs(ch) ? ' <span class="m">DFS</span>' : '') + '<br><span class="m">' + when(row.ts) + '</span><br>';
	if (c) {
		h += 'Interference estimate: <b>' + Math.round(c[2]) + '%</b><br>';
		h += c[3] ? (c[3] + ' network' + (c[3] > 1 ? 's' : '') + ' overlapping, strongest ' + c[4] + ' dBm') : 'No other networks heard';
		if (c[5] > 0) h += '<br><span class="m">Your mesh adds ' + Math.round(c[5]) + '%</span>';
	} else h += 'Not scanned';
	tip.innerHTML = h; placeTip(tip, ev.target.parentNode, x, y);
}
function renderEvents() {
	var evs = bandEvents(), shown = WI.allEvents ? evs : evs.slice(0, 10);
	if (!evs.length) { $('wiEvents').innerHTML = '<div class="empty" style="padding:16px 0">No events yet.</div>'; return; }
	var h = '<table class="t"><tr><th style="width:130px">Time</th><th style="width:190px">Event</th><th>Change</th></tr>';
	shown.forEach(function (e) {
		var detail = (e[5] && e[5] !== TAGS[e[2]]) ? e[5] : '';
		var change = (e[3] || e[4]) ? esc(e[3] || '') + (e[3] && e[4] ? ' → ' : '') + esc(e[4] || '') : '<span style="color:var(--muted)">' + (esc(detail).slice(0, 90) || '–') + '</span>';
		if (e[2] === 'initial') change = esc(e[4]);
		h += '<tr><td>' + when(e[0]) + '</td><td><span class="tag ' + esc(e[2]) + '">' + esc(TAGS[e[2]] || e[2]) + '</span>' + (e[1] === 'all' ? ' <span style="color:var(--muted)">all bands</span>' : '') + '</td><td>' + change + '</td></tr>';
	});
	h += '</table>';
	if (evs.length > 10) h += '<button type="button" class="more" onclick="WiFiInsight.toggleEvents()">' + (WI.allEvents ? 'Show fewer' : 'Show all ' + evs.length + ' events') + '</button>';
	$('wiEvents').innerHTML = h;
}

/* =================== SITE SURVEY =================== */
function aps() { return ((WI.scans && WI.scans.aps && WI.scans.aps[WI.band]) || []).slice(); }
function renderSurvey() {
	var list = aps(), last = WI.scans && WI.scans.last_scan && WI.scans.last_scan[WI.band];
	var others = list.filter(function (a) { return !a.own; }).length;
	$('wiSurveySub').textContent = list.length ? (others + ' other network' + (others === 1 ? '' : 's') + ' and ' + (list.length - others) + ' of yours, from the scan ' + ago(nowTs() - last) + '.') : '';
	renderSignalMap(list);
	renderApTable(list);
}
function mapGeo(w, h) {
	var ch = chans(), padL = 44, padR = 8, padT = 10, padB = 36, gw = w - padL - padR;
	var g = { padL: padL, padT: padT, padB: padB, gh: h - padT - padB, ch: ch, w: w };
	g.yOf = function (dbm) { var v = Math.max(-100, Math.min(-20, dbm)); return padT + (1 - (v + 100) / 80) * g.gh; };
	if (WI.band === '2g') {
		var f0 = freq(ch[0]) - 12, f1 = freq(ch[ch.length - 1]) + 12;
		g.xOf = function (f) { return padL + (f - f0) / (f1 - f0) * gw; };
		g.xCh = function (c) { return g.xOf(freq(c)); };
		g.edges = function (a) { var fc = freq(a.center); return [g.xOf(fc - a.width / 2), g.xOf(fc + a.width / 2)]; };
	} else {
		var slot = gw / ch.length;
		g.xCh = function (c) { var i = ch.indexOf(c); return i < 0 ? null : padL + (i + 0.5) * slot; };
		g.edges = function (a) {
			var sp = spanOf(a.center, a.width).filter(function (c) { return ch.indexOf(c) >= 0; });
			if (!sp.length) { if (ch.indexOf(a.ctl) < 0) return null; sp = [a.ctl]; }
			return [g.xCh(sp[0]) - slot / 2 + 2, g.xCh(sp[sp.length - 1]) + slot / 2 - 2];
		};
		g.slot = slot;
	}
	return g;
}
function renderSignalMap(list) {
	var cv = $('wiMap');
	if (!list.length || !chans().length) { cv.style.display = 'none'; $('wiMapEmpty').style.display = 'block'; $('wiMapEmpty').innerHTML = noScansMsg(); WI.mapShapes = null; return; }
	cv.style.display = 'block'; $('wiMapEmpty').style.display = 'none';
	var P = prepCanvas(cv, 270), ctx = P.ctx, g = mapGeo(P.w, 270), r = radio();
	// grid
	ctx.strokeStyle = C.grid; ctx.lineWidth = 1; ctx.fillStyle = C.tick; ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
	for (var d = -90; d <= -30; d += 10) { var y = g.yOf(d); ctx.beginPath(); ctx.moveTo(g.padL, y); ctx.lineTo(P.w - 8, y); ctx.stroke(); ctx.fillText(d, g.padL - 6, y); }
	ctx.save(); ctx.translate(10, g.padT + g.gh / 2); ctx.rotate(-Math.PI / 2); ctx.textAlign = 'center'; ctx.fillText('dBm', 0, 0); ctx.restore();
	// router's channel band
	if (r) {
		var e = g.edges({ center: r.center, width: r.width, ctl: r.ctl });
		if (e) { ctx.fillStyle = 'rgba(255,204,0,0.07)'; ctx.fillRect(e[0], g.padT, e[1] - e[0], g.gh); ctx.strokeStyle = 'rgba(255,204,0,0.6)'; ctx.setLineDash([4, 3]); ctx.strokeRect(e[0], g.padT, e[1] - e[0], g.gh); ctx.setLineDash([]); }
	}
	// shapes: weakest first so strong ones sit on top
	var shapes = [];
	list.slice().sort(function (a, b) { return a.rssi - b.rssi; }).forEach(function (a) {
		var e = g.edges(a); if (!e) return;
		shapes.push({ a: a, x0: e[0], x1: e[1], yp: g.yOf(a.rssi), base: g.padT + g.gh });
	});
	shapes.forEach(function (s) { drawShape(ctx, s, s === WI.mapHover); });
	// direct labels for the strongest few, skipping collisions
	var placed = [];
	ctx.textAlign = 'center'; ctx.textBaseline = 'bottom'; ctx.font = '11px system-ui, -apple-system, Segoe UI, sans-serif';
	shapes.slice().sort(function (a, b) { return b.a.rssi - a.a.rssi; }).slice(0, 8).forEach(function (s) {
		var label = s.a.ssid || '(hidden)', w = ctx.measureText(label).width, cx = (s.x0 + s.x1) / 2, y = s.yp - 4;
		var box = [cx - w / 2 - 3, y - 13, cx + w / 2 + 3, y];
		if (box[0] < g.padL || box[2] > P.w || box[1] < 0) return;
		for (var i = 0; i < placed.length; i++) { var p = placed[i]; if (!(box[2] < p[0] || box[0] > p[2] || box[3] < p[1] || box[1] > p[3])) return; }
		placed.push(box);
		ctx.fillStyle = s.a.own ? '#bfe9d6' : C.ink2;
		ctx.fillText(label, cx, y);
	});
	// channel axis
	ctx.fillStyle = C.tick; ctx.textAlign = 'center'; ctx.textBaseline = 'top';
	var y0 = g.padT + g.gh, every = (g.slot && g.slot < 22) ? 2 : 1;
	g.ch.forEach(function (c, j) { if (j % every === 0) ctx.fillText(c, g.xCh(c), y0 + 6); });
	if (WI.band === '5g') {
		ctx.strokeStyle = 'rgba(147,169,177,0.6)'; ctx.lineWidth = 1;
		var runs = [], cur = null;
		g.ch.forEach(function (c, j) { if (isDfs(c)) { if (!cur) { cur = { a: c, b: c }; runs.push(cur); } else cur.b = c; } else cur = null; });
		runs.forEach(function (run) {
			var x1 = g.xCh(run.a) - g.slot / 2 + 2, x2 = g.xCh(run.b) + g.slot / 2 - 2, yy = y0 + 23;
			ctx.beginPath(); ctx.moveTo(x1, yy - 3); ctx.lineTo(x1, yy); ctx.lineTo(x2, yy); ctx.lineTo(x2, yy - 3); ctx.stroke();
			ctx.fillText('DFS', (x1 + x2) / 2, yy + 1);
		});
	}
	WI.mapShapes = shapes; WI.mapGeo = g;
}
function drawShape(ctx, s, hot) {
	var col = s.a.own ? C.yours : C.others, w = s.x1 - s.x0, ramp = Math.min(w * 0.22, 18);
	ctx.beginPath();
	ctx.moveTo(s.x0, s.base);
	ctx.bezierCurveTo(s.x0 + ramp * 0.4, s.yp, s.x0 + ramp * 0.6, s.yp, s.x0 + ramp, s.yp);
	ctx.lineTo(s.x1 - ramp, s.yp);
	ctx.bezierCurveTo(s.x1 - ramp * 0.6, s.yp, s.x1 - ramp * 0.4, s.yp, s.x1, s.base);
	ctx.globalAlpha = hot ? 0.38 : (s.a.own ? 0.22 : 0.13); ctx.fillStyle = col; ctx.fill();
	ctx.globalAlpha = 1; ctx.lineWidth = hot ? 2.5 : 2; ctx.strokeStyle = col; ctx.setLineDash(s.a.own ? [] : []); ctx.stroke();
}
function mapHover(ev) {
	var shapes = WI.mapShapes, tip = $('wiMapTip');
	if (!shapes) return;
	var rect = ev.target.getBoundingClientRect(), x = ev.clientX - rect.left, y = ev.clientY - rect.top, hit = null;
	for (var i = shapes.length - 1; i >= 0; i--) { var s = shapes[i]; if (x >= s.x0 && x <= s.x1 && y >= s.yp - 3 && y <= s.base) { hit = s; break; } }
	if (hit !== WI.mapHover) { WI.mapHover = hit; renderSignalMap(aps()); }
	if (!hit) { tip.style.display = 'none'; return; }
	var a = hit.a;
	tip.innerHTML = '<b>' + (a.ssid ? esc(a.ssid) : '(hidden)') + '</b>' + (a.own ? ' <span class="m">your network</span>' : '') + '<br><span class="m">' + esc(a.bssid) + '</span><br>' +
		'Channel ' + a.ctl + ' · ' + a.width + ' MHz' + (isDfs(a.ctl) ? ' · DFS' : '') + '<br>Signal <b>' + a.rssi + ' dBm</b>' + (a.snr >= 0 ? ' · SNR ' + a.snr + ' dB' : '') + '<br>' +
		(PHY[a.phy] || '') + (a.sec ? ' · ' + esc(a.sec) : '') + (a.util >= 0 ? '<br>Reports ' + a.util + '% channel load' : '');
	placeTip(tip, ev.target.parentNode, x, y);
}
function renderApTable(list) {
	if (!list.length) { $('wiNets').innerHTML = '<div class="empty" style="padding:16px 0">No scan results yet.</div>'; return; }
	var k = WI.sortKey, d = WI.sortDir;
	list.sort(function (a, b) {
		var x = a[k], y = b[k];
		if (typeof x === 'string') return d * x.localeCompare(y);
		return d * ((x == null ? -999 : x) - (y == null ? -999 : y));
	});
	var col = function (key, label, cls) { return '<th class="sort' + (cls ? ' ' + cls : '') + '" onclick="WiFiInsight.sortBy(\'' + key + '\')">' + label + (k === key ? (d > 0 ? ' ▲' : ' ▼') : '') + '</th>'; };
	var h = '<table class="t"><tr>' + col('ssid', 'Network') + col('bssid', 'BSSID') + col('ctl', 'Ch', 'num') + col('width', 'Width', 'num') + col('phy', 'Standard') + col('sec', 'Security') + col('rssi', 'Signal') + col('util', 'Load', 'num') + '</tr>';
	list.forEach(function (a) {
		var pct = Math.max(4, Math.min(100, (a.rssi + 95) / 55 * 100));
		h += '<tr><td>' + (a.ssid ? esc(a.ssid) : '<span style="color:var(--muted)">(hidden)</span>') + (a.own ? '<span class="pill">Yours</span>' : '') + '</td>' +
			'<td class="mono">' + esc(a.bssid) + '</td><td class="num">' + a.ctl + (isDfs(a.ctl) ? '<span class="pill dfs">DFS</span>' : '') + '</td><td class="num">' + a.width + '</td>' +
			'<td>' + esc(PHY[a.phy] || '–') + '</td><td>' + esc(a.sec || '–') + '</td>' +
			'<td style="white-space:nowrap"><span class="sig"><i style="width:' + pct + '%"></i></span>' + a.rssi + ' dBm</td>' +
			'<td class="num">' + (a.util >= 0 ? a.util + '%' : '<span style="color:var(--muted)">–</span>') + '</td></tr>';
	});
	$('wiNets').innerHTML = h + '</table>';
}
function sortBy(k) { if (WI.sortKey === k) WI.sortDir = -WI.sortDir; else { WI.sortKey = k; WI.sortDir = (k === 'ssid' || k === 'bssid' || k === 'sec' || k === 'phy' || k === 'ctl') ? 1 : -1; } renderApTable(aps()); }

/* =================== CHANNEL STATISTICS =================== */
function channelLoads() {   // average and peak estimated load per channel across scans in range
	var info = scanRows(), ch = chans(), avg = {}, peak = {};
	ch.forEach(function (c) {
		var sum = 0, n = 0, pk = 0;
		info.rows.forEach(function (r) { var x = r.cells[c]; if (!x) return; var v = x[2] + (WI.showMesh ? x[5] : 0); v = Math.min(100, v); sum += v; n++; if (v > pk) pk = v; });
		avg[c] = n ? Math.round(sum / n * 10) / 10 : null; peak[c] = n ? Math.round(pk) : null;
	});
	return { avg: avg, peak: peak, n: info.rows.length, latestOnly: info.latestOnly };
}
function renderChannels() {
	var ch = chans(), list = aps(), r = radio(), cur = r ? spanOf(r.center, r.width) : [];
	if (!ch.length || !list.length && !(WI.scans && WI.scans.scans && WI.scans.scans[WI.band])) {
		drawChart('cnt', 'wiCntChart', 'bar', [], { empty: noScansMsg() });
		drawChart('load', 'wiLoadChart', 'bar', [], { empty: noScansMsg() });
		$('wiBest').innerHTML = ''; return;
	}
	var labels = ch.map(String), others = ch.map(function () { return 0; }), mine = ch.map(function () { return 0; });
	list.forEach(function (a) { var i = ch.indexOf(a.ctl); if (i < 0) return; if (a.own) mine[i]++; else others[i]++; });
	$('wiCntLegend').innerHTML = legendHTML('cnt', [['Other networks', C.others, 0], ['Yours', C.yours, 0]]);
	var barBase = { borderRadius: { topLeft: 4, topRight: 4 }, borderSkipped: 'bottom', categoryPercentage: 0.72, barPercentage: 0.9, borderWidth: { top: 2 }, borderColor: C.surface };
	var xCat = { type: 'category', grid: { display: false }, border: { color: '#4a585d' }, ticks: { color: C.tick, font: { size: 11 }, autoSkip: false, maxRotation: 0 } };
	drawChart('cnt', 'wiCntChart', 'bar', [
		Object.assign({ label: 'Other networks', data: others, backgroundColor: C.others }, barBase),
		Object.assign({ label: 'Yours', data: mine, backgroundColor: C.yours }, barBase)
	], { labels: labels, x: xCat, stacked: true, yMin: 0, yStep: 1, plugins: [curBand(ch.map(function (c, i) { return cur.indexOf(c) >= 0 ? i : -1; }).filter(function (i) { return i >= 0; }))], yFmt: function (v) { return Number.isInteger(v) ? v : ''; },
		ttTitle: function (it) { return 'Channel ' + it[0].label + (isDfs(+it[0].label) ? ' (DFS)' : ''); } });

	var L = channelLoads();
	$('wiLoadSub').textContent = (L.latestOnly ? 'Latest scan' : 'Average of ' + L.n + ' scan' + (L.n === 1 ? '' : 's') + ' in range') + '. Lower is better. The dashed band is the router’s current channel.';
	var data = ch.map(function (c) { return L.avg[c]; });
	var colors = data.map(function (v) { return rampColor(v == null ? 0 : Math.max(8, v)); });
	var maxV = Math.max.apply(null, data.map(function (v) { return v || 0; }));
	var curIdx = ch.map(function (c, i) { return cur.indexOf(c) >= 0 ? i : -1; }).filter(function (i) { return i >= 0; });
	drawChart('load', 'wiLoadChart', 'bar', [{ label: 'Estimated load', data: data, backgroundColor: colors, borderRadius: { topLeft: 4, topRight: 4 }, borderSkipped: 'bottom', categoryPercentage: 0.72, barPercentage: 0.9 }],
		{ labels: labels, x: xCat, yMin: 0, plugins: [curBand(curIdx)], yMax: Math.min(100, Math.max(20, Math.ceil((maxV + 5) / 10) * 10)), yFmt: pctFmt,
			ttTitle: function (it) { return 'Channel ' + it[0].label + (isDfs(+it[0].label) ? ' (DFS)' : '') + (cur.indexOf(+it[0].label) >= 0 ? ' · in use' : ''); },
			ttLabel: function (it) { var c = +it.label; return [' Average: ' + (it.parsed.y == null ? '–' : it.parsed.y + '%'), ' Peak: ' + (L.peak[c] == null ? '–' : L.peak[c] + '%')]; } });
	renderBest(L, ch, r);
}
function curBand(idx) {   // translucent band behind the router's channel(s), like the signal map
	return { id: 'wiCur', beforeDatasetsDraw: function (chart) {
		if (!idx.length) return;
		var x = chart.scales.x, a = chart.chartArea, ctx = chart.ctx, half = (x.getPixelForValue(1) - x.getPixelForValue(0)) / 2;
		var x0 = x.getPixelForValue(idx[0]) - half, x1 = x.getPixelForValue(idx[idx.length - 1]) + half;
		ctx.save(); ctx.fillStyle = 'rgba(255,204,0,0.08)'; ctx.fillRect(x0, a.top, x1 - x0, a.bottom - a.top);
		ctx.strokeStyle = 'rgba(255,204,0,0.6)'; ctx.setLineDash([4, 3]); ctx.strokeRect(x0, a.top, x1 - x0, a.bottom - a.top); ctx.restore();
	} };
}
var BLOCKS = {
	'5g': { 40: [[36, 40], [44, 48], [52, 56], [60, 64], [100, 104], [108, 112], [116, 120], [124, 128], [132, 136], [140, 144], [149, 153], [157, 161]],
		80: [[36, 40, 44, 48], [52, 56, 60, 64], [100, 104, 108, 112], [116, 120, 124, 128], [132, 136, 140, 144], [149, 153, 157, 161]],
		160: [[36, 40, 44, 48, 52, 56, 60, 64], [100, 104, 108, 112, 116, 120, 124, 128]] }
};
function renderBest(L, ch, r) {
	var widths = WI.band === '2g' ? [20] : [20, 40, 80, 160];
	if (r && widths.indexOf(r.width) < 0) widths.push(r.width);
	var rows = [];
	widths.forEach(function (w) {
		var cands = [];
		if (w === 20) {
			(WI.band === '2g' ? [1, 6, 11] : ch).forEach(function (c) { if (L.avg[c] != null) cands.push([c]); });
		} else ((BLOCKS[WI.band] || {})[w] || []).forEach(function (b) { if (b.every(function (c) { return L.avg[c] != null; })) cands.push(b); });
		if (!cands.length) return;
		var scored = cands.map(function (b) {
			var s = b.reduce(function (t, c) { return t + L.avg[c]; }, 0) / b.length, pk = Math.max.apply(null, b.map(function (c) { return L.peak[c]; }));
			return { b: b, s: Math.round(s * 10) / 10, pk: pk, dfs: b.some(isDfs) };
		}).sort(function (a, b) { return a.s - b.s || a.pk - b.pk || (a.dfs - b.dfs); });
		var best = scored[0], nonDfs = scored.filter(function (x) { return !x.dfs; })[0];
		var curBlk = null;
		if (r && r.width === w) { var sp = spanOf(r.center, r.width); curBlk = scored.filter(function (x) { return x.b[0] === sp[0]; })[0] || null; }
		rows.push({ w: w, best: best, nonDfs: nonDfs, cur: curBlk });
	});
	if (!rows.length) { $('wiBest').innerHTML = ''; return; }
	var name = function (x) { return x.b.length > 1 ? x.b[0] + '–' + x.b[x.b.length - 1] : String(x.b[0]); };
	var h = '<table class="t"><tr><th style="width:80px">Width</th><th>Quietest channel</th><th class="num">Est. load</th><th>Quietest without DFS</th><th class="num">Est. load</th><th>Your current</th></tr>';
	rows.forEach(function (x) {
		h += '<tr><td>' + x.w + ' MHz</td><td>' + name(x.best) + (x.best.dfs ? '<span class="pill dfs">DFS</span>' : '') + '</td><td class="num">' + x.best.s + '%</td>' +
			'<td>' + (x.nonDfs ? name(x.nonDfs) : '<span style="color:var(--muted)">–</span>') + '</td><td class="num">' + (x.nonDfs ? x.nonDfs.s + '%' : '') + '</td>' +
			'<td>' + (x.cur ? name(x.cur) + ' · ' + x.cur.s + '%<span class="pill cur">in use</span>' : '<span style="color:var(--muted)">–</span>') + '</td></tr>';
	});
	$('wiBest').innerHTML = h + '</table>';
}

/* =================== TROUBLESHOOTING =================== */
function renderTrouble() {
	var s = series(['tx', 'inbss', 'nocat', 'obss', 'nopkt', 'idle', 'glitch', 'badplcp', 'goodtx', 'badtx', 'noise']);
	var empty = s._n ? null : 'No samples in this range yet.';
	var area = function (label, data, col, first) { return { label: label, data: data, borderColor: col, backgroundColor: col + 'cc', fill: first ? 'origin' : '-1', borderWidth: 1 }; };
	$('wiAirLegend').innerHTML = legendHTML('air', [['Your TX', C.yours, 0], ['Your RX', C.rx, 0], ['Non-Wi-Fi', C.nonwifi, 0], ['Others Wi-Fi', C.others, 0], ['Unclassified', C.unclass, 0], ['Idle', C.idle, 0]]);
	drawChart('air', 'wiAirChart', 'line', [
		area('Your TX', s.tx, C.yours, 1), area('Your RX', s.inbss, C.rx), area('Non-Wi-Fi', s.nocat, C.nonwifi),
		area('Others Wi-Fi', s.obss, C.others), area('Unclassified', s.nopkt, C.unclass), area('Idle', s.idle, C.idle)
	], { R: s._R, stacked: true, yMin: 0, yMax: 110, yStep: 20, yFmt: function (v) { return v <= 100 ? v + '%' : ''; }, unit: '%', events: bandEvents(), plugins: [eventMarkers], empty: empty });

	$('wiGlLegend').innerHTML = legendHTML('gl', [['Rx glitches', C.unclass, 1], ['Bad PLCP', C.plcp, 1]]);
	drawChart('gl', 'wiGlChart', 'line', [
		{ label: 'Rx glitches', data: s.glitch, borderColor: C.unclass },
		{ label: 'Bad PLCP', data: s.badplcp, borderColor: C.plcp }
	], { R: s._R, yMin: 0, unit: '', empty: empty });

	$('wiTxLegend').innerHTML = legendHTML('txq', [['Successful', C.yours, 1], ['Failed', C.fail, 1, 1]]);
	drawChart('txq', 'wiTxChart', 'line', [
		{ label: 'Successful', data: s.goodtx, borderColor: C.yours },
		{ label: 'Failed', data: s.badtx, borderColor: C.fail, borderDash: [5, 3] }
	], { R: s._R, yMin: 0, yFmt: pctFmt, unit: '%', empty: empty });

	var nz = s.noise.filter(function (p) { return p.y != null; }).map(function (p) { return p.y; });
	var nMin = nz.length ? Math.floor((Math.min.apply(null, nz) - 3) / 5) * 5 : -100, nMax = nz.length ? Math.ceil((Math.max.apply(null, nz) + 3) / 5) * 5 : -60;
	drawChart('nz', 'wiNzChart', 'line', [{ label: 'Noise floor', data: s.noise, borderColor: C.ink2 }],
		{ R: s._R, yMin: nMin, yMax: nMax, yFmt: function (v) { return v + ' dBm'; }, unit: ' dBm', empty: empty });
	renderCounters();
}
function renderCounters() {
	var l = latestSample();
	if (!l) { $('wiCounters').innerHTML = '<div class="empty" style="padding:16px 0">No samples yet.</div>'; return; }
	var rows = [
		['tx', l[3], '%', 'Airtime spent transmitting'], ['inbss', l[4], '%', 'Receiving from your own clients'], ['obss', l[1], '%', 'Other networks on this channel'],
		['nocat', l[2], '%', 'Uncategorised energy (non-Wi-Fi)'], ['nopkt', l[11], '%', 'Busy, no packet decoded'], ['doze', l[12], '%', 'Radio in power save'],
		['txop', l[13], '%', 'Transmit opportunity available'], ['goodtx', l[14], '%', 'Successful transmissions'], ['badtx', l[15], '%', 'Failed transmissions'],
		['glitch', l[6], '', 'Receive glitches in the sample'], ['badplcp', l[16], '', 'Corrupted frame headers'], ['knoise', l[17], ' dBm', 'Noise estimate'], ['idle', l[5], '%', 'Channel idle']
	];
	var h = '<table class="t"><tr><th>Counter</th><th class="num">Value</th><th>Meaning</th></tr>';
	rows.forEach(function (r) { h += '<tr><td class="mono">' + r[0] + '</td><td class="num">' + (r[1] == null ? '–' : r[1] + r[2]) + '</td><td class="dim">' + r[3] + '</td></tr>'; });
	$('wiCounters').innerHTML = h + '</table>';
	$('wiCountersSub').innerHTML = 'Raw values from <code>wl chanim_stats</code>, ' + ago(nowTs() - l[0]) + '.';
}

/* =================== SETTINGS =================== */
function renderSettings() {
	var L = WI.live;
	if (!L) return;
	$('setSample').value = String(L.sample_interval);
	$('setScan').value = String(L.scan_interval);
	$('setRetain').value = String(L.retain_days);
	if (document.activeElement !== $('setOwn')) $('setOwn').value = L.extra_own || '';
	$('setOwnAuto').innerHTML = (L.own_ssids || []).length ? 'Detected automatically: ' + L.own_ssids.map(function (s) { return '<code>' + esc(s) + '</code>'; }).join(' ') : '';
	var mb = L.db_bytes ? (L.db_bytes / 1048576).toFixed(1) + ' MB' : '–';
	$('setStorage').innerHTML = '<code>' + esc(L.data_dir) + '</code> · ' + mb;
}
function saveSettings() {
	var own = $('setOwn').value.replace(/["$`\\]/g, '').trim();
	custom_settings.wifiinsight_sample = $('setSample').value;
	custom_settings.wifiinsight_scan = $('setScan').value;
	custom_settings.wifiinsight_retain = $('setRetain').value;
	custom_settings.wifiinsight_ownssids = own;
	document.form.amng_custom.value = JSON.stringify(custom_settings);
	document.form.action_script.value = 'start_wifiinsightconfig';
	document.form.action_wait.value = '3';
	document.form.submit();
	var b = $('setSave'); b.disabled = true; b.textContent = 'Saving…';
	setTimeout(function () {
		loadAll().then(function () { b.disabled = false; b.textContent = 'Save'; $('setSaved').style.display = 'inline'; setTimeout(function () { $('setSaved').style.display = 'none'; }, 4000); });
	}, 4000);
}

/* =================== shell =================== */
var VIEWS = [['insight', 'Insight'], ['survey', 'Site Survey'], ['channels', 'Channel Statistics'], ['trouble', 'Troubleshooting'], ['settings', 'Settings']];
function render() {
	var bands = ((WI.live && WI.live.radios) || []).map(function (r) { return r.band; });
	if (bands.length && bands.indexOf(WI.band) < 0) WI.band = bands[0];
	$('wiTabs').innerHTML = VIEWS.map(function (v) { return '<button type="button" class="' + (v[0] === WI.view ? 'on' : '') + '" onclick="WiFiInsight.setView(\'' + v[0] + '\')">' + v[1] + '</button>'; }).join('');
	$('wiBands').innerHTML = bands.map(function (b) { return '<button type="button" class="' + (b === WI.band ? 'on' : '') + '" onclick="WiFiInsight.setBand(\'' + b + '\')">' + BAND_NAME[b] + '</button>'; }).join('');
	$('wiRanges').innerHTML = [['10m', '10M'], ['1h', '1H'], ['12h', '12H'], ['1d', '1D'], ['7d', '7D']].map(function (x) { return '<button type="button" class="' + (x[0] === WI.range ? 'on' : '') + '" onclick="WiFiInsight.setRange(\'' + x[0] + '\')">' + x[1] + '</button>'; }).join('');
	var timed = WI.view === 'insight' || WI.view === 'trouble' || WI.view === 'channels';
	$('wiRanges').style.display = timed ? '' : 'none';
	$('wiBar').style.display = WI.view === 'settings' ? 'none' : '';
	VIEWS.forEach(function (v) { $('v-' + v[0]).className = 'view' + (v[0] === WI.view ? ' on' : ''); });
	renderView();
	if (WI.live) {
		var r = radio();
		$('wiFoot').innerHTML = 'Updated ' + hm(WI.live.generated) + ' · samples every ' + WI.live.sample_interval + ' s · neighbour scans ' +
			(WI.live.scan_interval > 0 ? 'every ' + WI.live.scan_interval + ' min' : 'off') + ' · history kept ' + WI.live.retain_days + ' days · v' + WI.live.version + (r ? ' · ' + r.iface : '');
	}
}
function renderView() {
	Object.keys(WI.charts).forEach(function (k) { WI.charts[k].destroy(); delete WI.charts[k]; });
	if (WI.view === 'insight') renderInsight();
	else if (WI.view === 'survey') renderSurvey();
	else if (WI.view === 'channels') renderChannels();
	else if (WI.view === 'trouble') renderTrouble();
	else renderSettings();
}
function setView(v) { WI.view = v; store('view', v); try { history.replaceState(null, '', '#' + v); } catch (e) {} render(); }
function setBand(b) { WI.band = b; store('band', b); WI.allEvents = false; WI.mapHover = null; render(); }
function setRange(r) { WI.range = r; store('range', r); if (r === '7d' && !WI.week) loadAll({ week: 1 }); else render(); }
function scanNow() {
	var btn = $('wiScanBtn');
	btn.disabled = true; btn.textContent = 'Scanning…';
	var before = (WI.scans && WI.scans.last_scan && WI.scans.last_scan[WI.band]) || 0, tries = 0;
	document.formScriptActions.action_script.value = 'start_wifiinsightscan';
	document.formScriptActions.submit();
	var done = function () { btn.disabled = false; btn.textContent = 'Scan now'; };
	var poll = setInterval(function () {
		tries++;
		getJSON('scans.htm').then(function (d) {
			var t = (d.last_scan && d.last_scan[WI.band]) || 0;
			if (t > before || tries > 20) { clearInterval(poll); WI.scans = d; done(); render(); }
		}).catch(function () { if (tries > 20) { clearInterval(poll); done(); } });
	}, 3000);
}
function boot() {
	var hash = (location.hash || '').replace('#', '');
	WI.view = VIEWS.some(function (v) { return v[0] === hash; }) ? hash : (store('view') || 'insight');
	if (!VIEWS.some(function (v) { return v[0] === WI.view; })) WI.view = 'insight';
	WI.band = store('band') || WI.band;
	WI.range = store('range') || WI.range;
	if (!RANGES[WI.range]) WI.range = '1h';
	WI.showMesh = store('mesh') === '1';
	$('wiMesh').checked = WI.showMesh; $('wiMesh2').checked = WI.showMesh;
	$('wiHeat').addEventListener('mousemove', heatHover);
	$('wiHeat').addEventListener('mouseleave', function () { $('wiTip').style.display = 'none'; });
	$('wiMap').addEventListener('mousemove', mapHover);
	$('wiMap').addEventListener('mouseleave', function () { $('wiMapTip').style.display = 'none'; if (WI.mapHover) { WI.mapHover = null; renderSignalMap(aps()); } });
	var rt; window.addEventListener('resize', function () { clearTimeout(rt); rt = setTimeout(renderView, 150); });
	$('wiRamp').style.background = 'linear-gradient(90deg,' + RAMP.join(',') + ')';
	render();
	loadAll();
	setInterval(function () { if (WI.view !== 'settings') loadAll({ live: 1 }); }, 60000);
	setInterval(function () { loadAll({ scans: 1, week: WI.range === '7d' ? 1 : 0 }); }, 300000);
}
function setMesh(on) { WI.showMesh = on; store('mesh', on ? '1' : '0'); $('wiMesh').checked = on; $('wiMesh2').checked = on; renderView(); }
function initial() {
	/* The firmware draws its menu here. If that ever fails, still show our page. */
	try { if (typeof show_menu === 'function') show_menu(); }
	catch (e) { if (window.console) console.error('WiFi Insight: show_menu() failed', e); }
	var page = window.location.pathname.substring(1);
	document.form.current_page.value = page; document.form.next_page.value = page;
	document.formScriptActions.current_page.value = page; document.formScriptActions.next_page.value = page;
	loadChart(function () { renderView(); });
	boot();
}

/* Chart.js is a UMD bundle: when RequireJS is on the page (the firmware loads it), it registers
   itself as an anonymous AMD module instead of setting window.Chart, and RequireJS throws
   "Mismatched anonymous define()". So fetch the code and run it with `define` hidden for that one
   synchronous step. The local copy is checked at install; the CDN copy is checked by SRI. */
function loadChart(done) {
	if (typeof Chart !== 'undefined') { done(); return; }
	var sources = [
		['/ext/wifiinsight/chart.umd.min.js', null],
		['https://cdn.jsdelivr.net/npm/chart.js@4.6.1/dist/chart.umd.min.js', 'sha384-Emf5ZVIUiarAdhkgtqK+5/Z5qIvM6QoVrS+qAVtfyZVuD5lIHrac0me485+Antp0']
	];
	(function next(i) {
		if (i >= sources.length) {
			var w = $('wiWarn');
			if (w) { w.innerHTML = 'Couldn\'t load the chart library. Run <code>/jffs/addons/wifiinsight/wifiinsight.sh install</code> again over SSH.'; w.style.display = 'block'; }
			return;
		}
		var opts = sources[i][1] ? { integrity: sources[i][1], mode: 'cors' } : { cache: 'no-cache', credentials: 'same-origin' };
		fetch(sources[i][0], opts)
			.then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
			.then(function (code) {
				var amd = window.define;
				window.define = undefined;
				try { (0, eval)(code); } finally { window.define = amd; }
				if (typeof Chart === 'undefined') throw new Error('Chart.js did not load');
				done();
			})
			.catch(function () { next(i + 1); });
	})(0);
}

window.initial = initial;
window.WiFiInsight = {
	setView: setView, setBand: setBand, setRange: setRange, scanNow: scanNow, setMesh: setMesh,
	saveSettings: saveSettings, sortBy: sortBy, toggleSeries: toggleSeries,
	toggleEvents: function () { WI.allEvents = !WI.allEvents; renderEvents(); },
	heatOption: function (key, on) { WI[key] = on; renderHeat(); },
	state: WI
};
})();
</script>
</head>
<body onload="initial();" class="bg">
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>
<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
<form method="post" name="form" action="start_apply.asp" target="hidden_frame">
<input type="hidden" name="current_page" value=""/>
<input type="hidden" name="next_page" value=""/>
<input type="hidden" name="group_id" value=""/>
<input type="hidden" name="modified" value="0"/>
<input type="hidden" name="action_mode" value="apply"/>
<input type="hidden" name="action_wait" value="3"/>
<input type="hidden" name="first_time" value=""/>
<input type="hidden" name="action_script" value=""/>
<input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get("preferred_lang"); %>"/>
<input type="hidden" name="firmver" value="<% nvram_get("firmver"); %>"/>
<input type="hidden" name="amng_custom" id="amng_custom" value=""/>
<table class="content" align="center" cellpadding="0" cellspacing="0">
<tr>
<td width="17">&nbsp;</td>
<td valign="top" width="202">
<div id="mainMenu"></div>
<div id="subMenu"></div>
</td>
<td valign="top">
<div id="tabMenu" class="submenuBlock"></div>
<table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
<tr>
<td align="left" valign="top">
<table width="760px" border="0" cellpadding="5" cellspacing="0" class="FormTitle" id="FormTitle">
<tr>
<td bgcolor="#4D595D" colspan="3" valign="top">
<div>&nbsp;</div>
<div class="formfonttitle">Wireless - WiFi Insight</div>
<div style="margin:10px 0 10px 5px;" class="splitLine"></div>
<div class="formfontdesc">Interference on your router's channel, why the channel changed, and how busy every channel around you is.</div>

<div id="wi">
	<div class="warn" id="wiWarn"></div>
	<div class="tabs" id="wiTabs"></div>
	<div class="bar" id="wiBar">
		<div class="seg" id="wiBands"></div>
		<div class="seg" id="wiRanges"></div>
		<div class="grow"></div>
		<button type="button" class="btn" id="wiScanBtn" onclick="WiFiInsight.scanNow()" title="Scans every channel now. Wi-Fi may pause for about a second.">Scan now</button>
	</div>

	<!-- ============ INSIGHT ============ -->
	<div class="view" id="v-insight">
		<div class="tiles" id="wiTiles"></div>
		<div class="card">
			<div class="head">
				<div class="grow"><h3>In-channel interference</h3><div class="sub">Share of airtime on the router's own channel. Dashed lines mark channel events.</div></div>
				<div class="legend" id="wiInsLegend"></div>
			</div>
			<div class="chartbox" id="wiInsChart"></div>
		</div>
		<div class="card">
			<div class="head">
				<div class="grow"><h3>Spectrum</h3><div class="sub" id="wiHeatSub"></div></div>
				<div class="legend">
					<label><input type="checkbox" checked onchange="WiFiInsight.heatOption('showActive',this.checked)"/>Active channel</label>
					<label><input type="checkbox" checked onchange="WiFiInsight.heatOption('showDfs',this.checked)"/>DFS</label>
					<label><input type="checkbox" id="wiMesh" onchange="WiFiInsight.setMesh(this.checked)"/>Include my mesh</label>
				</div>
			</div>
			<div class="rel">
				<canvas class="full" id="wiHeat"></canvas>
				<div class="empty" id="wiHeatEmpty" style="display:none"></div>
				<div class="tip" id="wiTip"></div>
			</div>
			<div class="foot">
				<span class="ramp">Clean <i id="wiRamp"></i> Busy</span>
				<span><span style="display:inline-block;width:14px;height:10px;border:2px solid #ffcc00;border-radius:2px;vertical-align:-1px;margin-right:5px"></span>Router's channel</span>
			</div>
		</div>
		<div class="card">
			<div class="head"><div class="grow"><h3>Channel events</h3><div class="sub">Channel and bandwidth changes, radar detections and restarts.</div></div></div>
			<div id="wiEvents"></div>
		</div>
	</div>

	<!-- ============ SITE SURVEY ============ -->
	<div class="view" id="v-survey">
		<div class="card">
			<div class="head">
				<div class="grow"><h3>Signal map</h3><div class="sub" id="wiSurveySub"></div></div>
				<div class="legend"><span class="li"><span class="sq" style="background:var(--others)"></span>Other networks</span><span class="li"><span class="sq" style="background:var(--yours)"></span>Your network</span><span class="li"><span class="sq" style="background:rgba(255,204,0,0.25);border:1px dashed #ffcc00"></span>Router's channel</span></div>
			</div>
			<div class="rel">
				<canvas class="full" id="wiMap"></canvas>
				<div class="empty" id="wiMapEmpty" style="display:none"></div>
				<div class="tip" id="wiMapTip"></div>
			</div>
		</div>
		<div class="card">
			<div class="head"><div class="grow"><h3>Networks</h3><div class="sub">Click a column to sort.</div></div></div>
			<div id="wiNets"></div>
		</div>
	</div>

	<!-- ============ CHANNEL STATISTICS ============ -->
	<div class="view" id="v-channels">
		<div class="card">
			<div class="head"><div class="grow"><h3>Networks per channel</h3><div class="sub">Counted by primary channel in the latest scan.</div></div><div class="legend" id="wiCntLegend"></div></div>
			<div class="chartbox sm" id="wiCntChart"></div>
		</div>
		<div class="card">
			<div class="head">
				<div class="grow"><h3>Estimated load per channel</h3><div class="sub" id="wiLoadSub"></div></div>
				<div class="legend"><label><input type="checkbox" id="wiMesh2" onchange="WiFiInsight.setMesh(this.checked)"/>Include my mesh</label></div>
			</div>
			<div class="chartbox sm" id="wiLoadChart"></div>
		</div>
		<div class="card">
			<div class="head"><div class="grow"><h3>Quietest options</h3><div class="sub">Best channel for each width, based on the estimated load above. DFS channels can be forced to change if radar is detected.</div></div></div>
			<div id="wiBest"></div>
		</div>
	</div>

	<!-- ============ TROUBLESHOOTING ============ -->
	<div class="view" id="v-trouble">
		<div class="card">
			<div class="head"><div class="grow"><h3>Airtime breakdown</h3><div class="sub">Where the router's channel time goes, stacked. Values come from the radio and can add up to slightly over 100%.</div></div></div>
			<div class="legend" id="wiAirLegend" style="justify-content:flex-start;margin-bottom:6px"></div>
			<div class="chartbox" id="wiAirChart"></div>
		</div>
		<div class="grid2">
			<div class="card">
				<div class="head"><div class="grow"><h3>Glitch counter</h3><div class="sub">Receive errors per sample.</div></div></div>
				<div class="legend" id="wiGlLegend" style="justify-content:flex-start;margin-bottom:6px"></div>
				<div class="chartbox sm" id="wiGlChart"></div>
			</div>
			<div class="card">
				<div class="head"><div class="grow"><h3>Transmit quality</h3><div class="sub">Airtime of successful vs failed transmissions.</div></div></div>
				<div class="legend" id="wiTxLegend" style="justify-content:flex-start;margin-bottom:6px"></div>
				<div class="chartbox sm" id="wiTxChart"></div>
			</div>
		</div>
		<div class="gridgap"></div>
		<div class="card">
			<div class="head"><div class="grow"><h3>Noise floor</h3><div class="sub">Lower (more negative) is better.</div></div></div>
			<div class="chartbox sm" id="wiNzChart"></div>
		</div>
		<div class="card">
			<div class="head"><div class="grow"><h3>Latest counters</h3><div class="sub" id="wiCountersSub"></div></div></div>
			<div id="wiCounters"></div>
		</div>
	</div>

	<!-- ============ SETTINGS ============ -->
	<div class="view" id="v-settings">
		<div class="card">
			<div class="head"><div class="grow"><h3>Data collection</h3></div></div>
			<div class="form">
				<div class="lbl">Sample interval</div>
				<div><select id="setSample"><option value="30">Every 30 seconds</option><option value="60">Every minute</option></select>
					<div class="hint">How often the router's own channel is measured. Reading these counters doesn't affect Wi-Fi.</div></div>
				<div class="lbl">Neighbour scans</div>
				<div><select id="setScan"><option value="0">Off</option><option value="15">Every 15 minutes</option><option value="30">Every 30 minutes</option><option value="60">Every hour</option><option value="120">Every 2 hours</option><option value="180">Every 3 hours</option><option value="360">Every 6 hours</option></select>
					<div class="hint">Feeds the spectrum map, site survey and channel statistics. Each scan pauses Wi-Fi for about a second.</div></div>
				<div class="lbl">Keep history for</div>
				<div><select id="setRetain"><option value="7">7 days</option><option value="14">14 days</option><option value="30">30 days</option><option value="60">60 days</option><option value="90">90 days</option><option value="180">180 days</option></select>
					<div class="hint">Channel events are kept for a year.</div></div>
				<div class="lbl">Also treat as mine</div>
				<div><input type="text" id="setOwn" placeholder="SSID one|SSID two" maxlength="200"/>
					<div class="hint">Networks listed here are shown as yours and left out of the interference estimate. Separate names with <code>|</code>. <span id="setOwnAuto"></span></div></div>
				<div class="lbl">Storage</div>
				<div style="padding-top:6px" id="setStorage"></div>
				<div></div>
				<div><button type="button" class="btn primary" id="setSave" onclick="WiFiInsight.saveSettings()">Save</button><span class="saved" id="setSaved">Saved</span></div>
			</div>
		</div>
		<div class="card">
			<div class="head"><div class="grow"><h3>Command line</h3></div></div>
			<div class="sub" style="line-height:1.8">
				Status: <code>/jffs/addons/wifiinsight/wifiinsight.sh status</code><br/>
				Uninstall: <code>/jffs/addons/wifiinsight/wifiinsight.sh uninstall</code> (add <code>--keep-data</code> to keep history)
			</div>
		</div>
	</div>

	<div class="note">
		<b>Others Wi-Fi</b>: airtime used by networks that aren't yours, including your mesh node's separate access point when it shares the channel.
		<b>Non-Wi-Fi</b>: energy from devices such as microwaves, baby monitors and Bluetooth. Spectrum and channel load are estimates built from periodic scans.
		<br/><span id="wiFoot"></span>
	</div>
</div>

</td>
</tr>
</table>
</td>
</tr>
</table>
</td>
<td width="10" align="center" valign="top">&nbsp;</td>
</tr>
</table>
</form>
<form method="post" name="formScriptActions" action="/start_apply.asp" target="hidden_frame">
<input type="hidden" name="productid" value="<% nvram_get("productid"); %>"/>
<input type="hidden" name="current_page" value=""/>
<input type="hidden" name="next_page" value=""/>
<input type="hidden" name="action_mode" value="apply"/>
<input type="hidden" name="action_script" value=""/>
<input type="hidden" name="action_wait" value=""/>
</form>
<div id="footer"></div>
</body>
</html>
